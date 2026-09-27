"""Negative tests for verify_mec_data.py.

A guardrail that has never been seen to fire is not a guardrail. This
perturbs the data in each way the validator is supposed to catch, asserts the
validator fails, and restores the original file byte-for-byte.
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
BACKEND = APP.parent / "pcos_ml_project" / "app_backend" / "eligibility_data.py"
VALIDATOR = APP / "tool" / "verify_mec_data.py"
CROSSWALK = APP / "mec_crosswalk.json"

CASES = [
    ("golden rating changed",
     lambda s: s.replace('"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 2,',
                         '"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 4,')),
    ("orphaned backend id",
     lambda s: s.replace('"obesity_bmi30"', '"obesity_bmi30plus"')),
    ("header node given a rating",
     lambda s: s.replace('CONDITIONS_BY_ID = {c.id: c for c in CONDITIONS}',
                         'CONDITIONS.append(ConditionEntry("art_nnrti", "NNRTIs", '
                         '{"chc": 1}))\nCONDITIONS_BY_ID = {c.id: c for c in CONDITIONS}')),
    # "a) Smoker" is a selectable app row, so it is not a registry header, but
    # WHO rates only its cigarettes-per-day children. Serving it would invent
    # an all-clear.
    ("category parent given a rating",
     lambda s: s.replace('CONDITIONS_BY_ID = {c.id: c for c in CONDITIONS}',
                         'CONDITIONS.append(ConditionEntry("smoking_35_plus", '
                         '"Smoking", {"chc": 1}))\nCONDITIONS_BY_ID = {c.id: c for c in CONDITIONS}')),
    ("category out of range",
     lambda s: s.replace('"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 2,',
                         '"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 7,')),
    ("unknown method id",
     lambda s: s.replace('"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 2,',
                         '"obesity_bmi30", "Obesity, BMI \\u226530 kg/m\\u00b2",\n        {"chc": 2, "vacuum": 1,')),
    ("verified condition dropped",
     lambda s: re.sub(r'    ConditionEntry\(\n        "obesity_bmi30".*?\n    \),\n', '', s, flags=re.S)),
]

# These mutate the GENERATED module rather than the hand-curated one, because
# the provenance gate reads provenance off the merged CONDITIONS list and a
# machine-extracted row is the only thing that can falsely claim review.
# Claiming a human checked a rating nobody checked is a false claim about the
# review status of medical guidance, so it must fail the build.
# NB: build_matrix.py writes values with repr(), so they are single-quoted,
# and the emitted line is long enough to wrap, so match the value alone.
EXTRACTED_CASES = [
    ("unreviewed hand_verified claim",
     lambda s: s.replace("'extracted_pending_review'", "'hand_verified'", 1)),
    ("invented provenance value",
     lambda s: s.replace("'extracted_pending_review'", "'trust_me'", 1)),
]

# The crosswalk conflict check reads a second file, so it needs its own
# mutation target: perturb the extracted rating for a served, verified id and
# confirm the validator reports the disagreement rather than passing quietly.
# Mutating via json (not string replace) because the file is written with
# indent=1, so keys are not on one line.
CROSSWALK_CASES = [
    ("crosswalk rating disagrees with served data",
     lambda d: _bump(d, "obesity_bmi30", "chc", 2, 3)),
    # WHO prints composites like "2/3" where its own guidance is split. Picking
    # a half would be inventing a category, so a composite must never be
    # recorded as a rating -- not even in a state that is not served.
    ("composite recorded as a rating",
     lambda d: _composite(d)),
]

# The two cases above act on a different file, the raw extraction output, so
# they get their own mutation target.
RAW = APP / "who_mec_raw.json"


def _composite(doc):
    for c in doc["conditions"]:
        if c["state"] in ("verified", "extracted") and c["ratings"]:
            method, phases = next(iter(c["ratings"].items()))
            phase = next(iter(phases))
            phases[phase]["category"] = "2/3"
            return json.dumps(doc, indent=1, ensure_ascii=False)
    raise AssertionError("no served condition with ratings to composite")


def _contaminate(doc):
    table = next(iter(doc))
    doc[table]["rows"].append({
        "page": 223, "path": "ANTIRETROVIRAL THERAPY > Raltegravir (RAL)",
        "condition": "Raltegravir (RAL)", "raw": "1 3 3",
        "canonical": ["1", "3", "3"], "by_method": None})
    return json.dumps(doc, indent=1, ensure_ascii=False)


RAW_CASES = [
    # The drug-interaction annex tables share the condition tables' page ranges
    # but not their columns. Reading them as conditions produced a barrier
    # category of 3 (delay) for Raltegravir, where WHO rates every
    # antiretroviral as usable with barrier methods.
    ("drug-interaction row in extraction", _contaminate),
]


def _bump(doc, cid, method, old, new):
    for c in doc["conditions"]:
        if c["id"] == cid and c["state"] == "verified":
            phase = next(iter(c["ratings"][method]))
            if c["ratings"][method][phase]["category"] != old:
                raise AssertionError(
                    f"{cid}.{method}[{phase}] is "
                    f"{c['ratings'][method][phase]['category']!r}, not {old!r}")
            c["ratings"][method][phase]["category"] = new
            return json.dumps(doc, indent=1, ensure_ascii=False)
    raise AssertionError(f"no verified {cid} in crosswalk")

# These two mutate the GENERATED module rather than the hand-curated one,
# because the provenance gate reads provenance off the merged CONDITIONS list
# and a machine-extracted row is the only thing that can falsely claim review.
EXTRACTED = BACKEND.parent / "eligibility_extracted.py"


def _run_validator():
    return subprocess.run([sys.executable, str(VALIDATOR)], cwd=APP,
                          capture_output=True, text=True)


def _report(name, result, failures):
    if result.returncode == 0:
        print(f"{name:<29} NOT CAUGHT  <-- guardrail is broken")
        return failures + 1
    first = next((l.strip(" -") for l in result.stdout.splitlines()
                  if l.strip().startswith("- ")), "?")
    print(f"{name:<29} caught  ({first[:58]})")
    return failures


original = BACKEND.read_text(encoding="utf-8")
backup = Path(tempfile.mkdtemp()) / "eligibility_data.py"
shutil.copy2(BACKEND, backup)

crosswalk_original = None
crosswalk_backup = None
if CROSSWALK.exists():
    crosswalk_original = CROSSWALK.read_text(encoding="utf-8")
    crosswalk_backup = Path(tempfile.mkdtemp()) / CROSSWALK.name
    shutil.copy2(CROSSWALK, crosswalk_backup)

extracted_original = None
extracted_backup = None
if EXTRACTED.exists():
    extracted_original = EXTRACTED.read_text(encoding="utf-8")
    extracted_backup = Path(tempfile.mkdtemp()) / EXTRACTED.name
    shutil.copy2(EXTRACTED, extracted_backup)

raw_original = None
raw_backup = None
if RAW.exists():
    raw_original = RAW.read_text(encoding="utf-8")
    raw_backup = Path(tempfile.mkdtemp()) / RAW.name
    shutil.copy2(RAW, raw_backup)

try:
    # Baseline: the real data must pass.
    r = subprocess.run([sys.executable, str(VALIDATOR)], cwd=APP,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("BASELINE FAILED -- validator rejects the real data:\n", r.stdout)
        sys.exit(1)
    print("baseline                      PASSES (as expected)")

    failures = 0
    for name, mutate in CASES:
        mutated = mutate(original)
        if mutated == original:
            print(f"{name:<29} SETUP BROKEN (mutation did not apply)")
            failures += 1
            continue
        BACKEND.write_text(mutated, encoding="utf-8")
        r = subprocess.run([sys.executable, str(VALIDATOR)], cwd=APP,
                           capture_output=True, text=True)
        if r.returncode == 0:
            print(f"{name:<29} NOT CAUGHT  <-- guardrail is broken")
            failures += 1
        else:
            first = next((l.strip(" -") for l in r.stdout.splitlines()
                          if l.strip().startswith("- ")), "?")
            print(f"{name:<29} caught  ({first[:58]})")

    # Restore the backend before the crosswalk cases: otherwise the previous
    # mutation is still in place and its error masks the crosswalk check, so
    # the test would pass for the wrong reason.
    BACKEND.write_text(original, encoding="utf-8")

    for name, mutate in EXTRACTED_CASES:
        mutated = mutate(extracted_original)
        if mutated == extracted_original:
            print(f"{name:<29} SETUP BROKEN (mutation did not apply)")
            failures += 1
            continue
        EXTRACTED.write_text(mutated, encoding="utf-8")
        result = _run_validator()
        EXTRACTED.write_text(extracted_original, encoding="utf-8")
        failures = _report(name, result, failures)

    for name, mutate in CROSSWALK_CASES:
        try:
            mutated = mutate(json.loads(crosswalk_original))
        except AssertionError as exc:
            print(f"{name:<29} SETUP BROKEN ({exc})")
            failures += 1
            continue
        if mutated == crosswalk_original:
            print(f"{name:<29} SETUP BROKEN (mutation did not apply)")
            failures += 1
            continue
        CROSSWALK.write_text(mutated, encoding="utf-8")
        result = _run_validator()
        CROSSWALK.write_text(crosswalk_original, encoding="utf-8")
        failures = _report(name, result, failures)

    for name, mutate in RAW_CASES:
        try:
            mutated = mutate(json.loads(raw_original))
        except AssertionError as exc:
            print(f"{name:<29} SETUP BROKEN ({exc})")
            failures += 1
            continue
        if mutated == raw_original:
            print(f"{name:<29} SETUP BROKEN (mutation did not apply)")
            failures += 1
            continue
        RAW.write_text(mutated, encoding="utf-8")
        result = _run_validator()
        RAW.write_text(raw_original, encoding="utf-8")
        failures = _report(name, result, failures)

    BACKEND.write_text(original, encoding="utf-8")
    r = subprocess.run([sys.executable, str(VALIDATOR)], cwd=APP,
                       capture_output=True, text=True)
    restored = r.returncode == 0
    print(f"\nfile restored and valid       "
          f"{'OK' if restored else 'RESTORE FAILED'}")
    sys.exit(1 if (failures or not restored) else 0)
finally:
    if BACKEND.read_text(encoding="utf-8") != original:
        shutil.copy2(backup, BACKEND)
        print("original content force-restored")
    if (crosswalk_original is not None
            and CROSSWALK.read_text(encoding="utf-8") != crosswalk_original):
        shutil.copy2(crosswalk_backup, CROSSWALK)
        print("crosswalk force-restored")
    if (extracted_original is not None
            and EXTRACTED.read_text(encoding="utf-8") != extracted_original):
        shutil.copy2(extracted_backup, EXTRACTED)
    if (raw_original is not None
            and RAW.read_text(encoding="utf-8") != raw_original):
        shutil.copy2(raw_backup, RAW)
        print("raw force-restored")
        print("generated matrix force-restored")
