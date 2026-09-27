"""Verify the WHO MEC eligibility data against the Flutter app taxonomy.

Run:  python tool/verify_mec_data.py

This is the safety net for populating the WHO MEC matrix. It enforces every
invariant that must hold before any rating is trusted, and it fails loudly
rather than warning. Exit code is non-zero on any failure, so it can be wired
into CI.

Checks
------
1.  Every condition the backend serves exists in the app's taxonomy.
    (A backend id the app has never heard of is DEAD: the app intersects its
    local list with /conditions and silently drops it. This is not
    theoretical -- 7 of 12 curated ids were dead until 2026-09-26.)
2.  Every app condition has a human-readable label. An unlabelled condition
    either stays invisible in the picker or renders as a raw snake_case id.
3.  Every category is an int in 1..4.
4.  Every rating targets a known method id.
5.  Header nodes (parents, e.g. art_nnrti) are never rated. WHO MEC gives
    categories to leaf rows only; rating a header fabricates an all-clear.
6.  GOLDEN FIXTURE -- the ratings that were hand-verified against the WHO MEC
    5th edition must not change. Any edit to them is a regression until a
    human re-checks the source.
"""

import json
import re
import sys
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
BACKEND_DIR = APP.parent / "pcos_ml_project"
sys.path.insert(0, str(BACKEND_DIR))
sys.path.insert(0, str(APP / "tool"))

from app_backend import eligibility_data as ed  # noqa: E402
# Imported, not re-declared, so the extractor and the validator can never drift
# apart on which sections are drug-interaction tables.
from extract_who_mec import DRUG_INTERACTION_SECTIONS  # noqa: E402

# WHO MEC 5th edition (2015) condition headings that are structure, not
# conditions. They group their children and carry no category of their own.
HEADER_NODES = {
    "art_integrase", "art_nnrti", "art_nrti", "art_pi",
    "breast_cancer_category",
}

# Nodes that must never carry a category, but which are NOT registry header
# nodes -- they are selectable rows in the app taxonomy, so they are still
# counted as leaf rows. WHO MEC rates only the children:
#   * smoking_35_plus ("a) Smoker") has no category of its own; WHO splits it
#     into cigarettes-per-day sub-rows.
# Rating either of these would hand the user a fabricated all-clear, so the
# check below is deliberately wider than HEADER_NODES. Kept in step with
# tool/crosswalk.py, which refuses to emit them for the same reason.
NEVER_RATED = HEADER_NODES | {"smoking_35_plus"}

# Conditions transcribed by hand into eligibility_data.py's CONDITIONS literal
# before the extraction pipeline existed. They are the original curated set and
# predate the provenance field, so they keep the `hand_verified` default.
# `diabetes_with_vascular` is here rather than in GOLDEN because the frozen
# fixture does not include it; it was still hand-transcribed from the printed
# tables. Anything NOT in this list and NOT in GOLDEN must be labelled
# extracted_pending_review.
HAND_TRANSCRIBED = {
    "smoking_35_plus_under15cig", "smoking_35_plus_15plus_cig",
    "migraine_with_aura", "vte_current", "vte_history",
    "hypertension_elevated_160_plus", "current_breast_cancer",
    "cirrhosis_severe", "diabetes_with_vascular", "breastfeeding_lt6weeks",
    "obesity_bmi30",
}

# Frozen 2026-09-26. Verified by hand against the WHO MEC 5th edition.
# Do NOT edit to make a failing check pass.
GOLDEN = {
    "smoking_35_plus_under15cig": {"chc": 3, "pop": 1, "poi": 1, "impl": 1,
                                   "lng_iud": 1, "cu_iud": 1, "barrier": 1,
                                   "lam": 1, "fem_ster": 1, "male_ster": 1},
    "smoking_35_plus_15plus_cig": {"chc": 4, "pop": 1, "poi": 1, "impl": 1,
                                   "lng_iud": 1, "cu_iud": 1, "barrier": 1,
                                   "lam": 1, "fem_ster": 1, "male_ster": 1},
    "migraine_with_aura": {"chc": 4, "pop": 2, "poi": 2, "impl": 2,
                           "lng_iud": 2, "cu_iud": 1, "barrier": 1,
                           "lam": 1, "fem_ster": 1, "male_ster": 1},
    "vte_current": {"chc": 4, "pop": 3, "poi": 3, "impl": 3, "lng_iud": 3,
                    "cu_iud": 1, "barrier": 1, "lam": 1, "fem_ster": 1,
                    "male_ster": 1},
    "vte_history": {"chc": 4, "pop": 2, "poi": 2, "impl": 2, "lng_iud": 2,
                    "cu_iud": 1, "barrier": 1, "lam": 1, "fem_ster": 1,
                    "male_ster": 1},
    "hypertension_elevated_160_plus": {"chc": 4, "pop": 2, "poi": 3, "impl": 2,
                                      "lng_iud": 2, "cu_iud": 1, "barrier": 1,
                                      "lam": 1, "fem_ster": 1, "male_ster": 1},
    "current_breast_cancer": {"chc": 4, "pop": 4, "poi": 4, "impl": 4,
                              "lng_iud": 4, "cu_iud": 1, "barrier": 1,
                              "lam": 1, "fem_ster": 1, "male_ster": 1},
    "cirrhosis_severe": {"chc": 4, "pop": 3, "poi": 3, "impl": 3,
                         "lng_iud": 2, "cu_iud": 1, "barrier": 1, "lam": 1,
                         "fem_ster": 1, "male_ster": 1},
    "diabetes_with_vascular": {"chc": 4, "pop": 2, "poi": 3, "impl": 2,
                               "lng_iud": 2, "cu_iud": 1, "barrier": 1,
                               "lam": 1, "fem_ster": 1, "male_ster": 1},
    "breastfeeding_lt6weeks": {"chc": 4, "pop": 2, "poi": 2, "impl": 2,
                               "lng_iud": 2, "cu_iud": 2, "barrier": 1,
                               "lam": 1, "fem_ster": 1, "male_ster": 1},
    "postpartum_lt21days_not_breastfeeding": {"chc": 3, "pop": 1, "poi": 1,
                                              "impl": 1, "lng_iud": 2,
                                              "cu_iud": 2, "barrier": 1,
                                              "lam": 1, "fem_ster": 1,
                                              "male_ster": 1},
    "obesity_bmi30": {"chc": 2, "pop": 1, "poi": 1, "impl": 1, "lng_iud": 1,
                      "cu_iud": 1, "barrier": 1, "lam": 1, "fem_ster": 1,
                      "male_ster": 1},
}

# Verified against WHO MEC 5th ed. but deliberately not served, because the
# app has no row they can honestly attach to. See PENDING_RATINGS.
STAGED = {"postpartum_lt21days_not_breastfeeding"}

failures: list[str] = []
notes: list[str] = []


def fail(msg):
    failures.append(msg)


# --- app taxonomy ------------------------------------------------------------
reg = json.loads((APP / "mec_registry.json").read_text(encoding="utf-8"))
app = {c["id"]: c for c in reg["conditions"]}
leaf_ids = set(app) - HEADER_NODES

# --- 1. no orphaned backend ids ---------------------------------------------
orphans = [c.id for c in ed.CONDITIONS if c.id not in app]
for cid in orphans:
    fail(f"orphan: backend serves '{cid}' but the app taxonomy has no such id "
         f"-- the app will silently drop it (unreachable)")

# --- 2. every app condition has a label -------------------------------------
for cid, entry in sorted(app.items()):
    if not entry.get("label"):
        fail(f"unlabelled: app condition '{cid}' has no human-readable label")

# --- 3/4. rating shape -------------------------------------------------------
for entry in ed.CONDITIONS:
    for method, cat in entry.categories.items():
        if method not in ed.METHOD_IDS:
            fail(f"bad method: '{entry.id}' rates unknown method '{method}'")
        if not isinstance(cat, int) or isinstance(cat, bool) or not 1 <= cat <= 4:
            fail(f"bad category: '{entry.id}'[{method}] = {cat!r}, must be int 1-4")

# --- 5. header nodes must not be rated --------------------------------------
for entry in ed.CONDITIONS:
    if entry.id in NEVER_RATED:
        why = ("is a WHO MEC group heading with no category of its own"
               if entry.id in HEADER_NODES else
               "is a parent row; WHO MEC rates only its child rows")
        fail(f"header rated: '{entry.id}' {why} -- it must never receive a "
             f"category")

# --- 5b. provenance must be earned, not asserted ----------------------------
# `hand_verified` is a claim that a person checked the rating against the
# printed WHO MEC 5th-edition page. Only the frozen golden fixture carries that
# claim, so any other condition asserting it is a false claim about the review
# status of medical guidance and fails the build. Everything else must be
# labelled `extracted_pending_review`, which the app surfaces as such.
VALID_PROVENANCE = {"hand_verified", "extracted_pending_review"}
for entry in ed.CONDITIONS:
    prov = getattr(entry, "provenance", "hand_verified")
    if prov not in VALID_PROVENANCE:
        fail(f"provenance '{prov}' on '{entry.id}' is not one of "
             f"{sorted(VALID_PROVENANCE)}")
    elif prov == "hand_verified" and entry.id not in GOLDEN and entry.id not in STAGED:
        if entry.id not in HAND_TRANSCRIBED:
            fail(f"UNREVIEWED CLAIM: '{entry.id}' is marked hand_verified but is "
                 f"not in the golden fixture -- a human must check it against the "
                 f"printed WHO page before it can claim review, or it must be "
                 f"marked extracted_pending_review")

# --- 6. golden fixture -------------------------------------------------------
for cid, expected in sorted(GOLDEN.items()):
    actual = ed.CONDITIONS_BY_ID.get(cid)
    if cid in STAGED:
        if actual is not None:
            fail(f"staged condition '{cid}' is being served; it has no valid "
                 f"app row -- keep it in PENDING_RATINGS or add a matching "
                 f"app row first")
        else:
            staged = ed.PENDING_RATINGS.get(cid)
            if staged is None:
                fail(f"staged condition '{cid}' vanished from PENDING_RATINGS")
            elif staged["categories"] != expected:
                fail(f"GOLDEN REGRESSION: staged '{cid}' ratings changed")
        continue
    if actual is None:
        fail(f"golden missing: verified condition '{cid}' is gone from the "
             f"backend -- coverage regressed")
        continue
    if actual.categories != expected:
        diff = {k: (expected.get(k), actual.categories.get(k))
                for k in set(expected) | set(actual.categories)
                if expected.get(k) != actual.categories.get(k)}
        fail(f"GOLDEN REGRESSION: '{cid}' ratings changed {diff} -- these were "
             f"verified by hand; re-check the WHO source before accepting")

# --- 7. nothing may be silently dropped from the golden set ------------------
missing_staged = STAGED - set(ed.PENDING_RATINGS)
if missing_staged:
    fail(f"STAGED ids with no PENDING_RATINGS entry: {sorted(missing_staged)}")

extra = set(ed.CONDITIONS_BY_ID) - set(GOLDEN)
if extra:
    notes.append(f"{len(extra)} condition(s) present but not in the golden "
                 f"fixture (expected while the matrix is being populated): "
                 f"{', '.join(sorted(extra))}")

# --- 8. the independent WHO extraction must agree with what is served --------
# The crosswalk is derived from the official PDF by a separate code path
# (coordinate extraction), so where it covers a served rating it is an
# independent check on the hand transcription. Divergence means one of the two
# is wrong and must be re-checked against the printed page before serving.
CROSSWALK = Path(__file__).resolve().parents[1] / "mec_crosswalk.json"
if CROSSWALK.exists():
    cw = {c["id"]: c for c in
          json.loads(CROSSWALK.read_text(encoding="utf-8"))["conditions"]}
    agree = conflicts = 0
    for c in ed.CONDITIONS:
        w = cw.get(c.id)
        if not w or w["state"] != "verified":
            continue
        for method, phases in w["ratings"].items():
            served = c.categories.get(method)
            if served is None:
                continue
            if int(served) == int(phases["I"]["category"]):
                agree += 1
            else:
                conflicts += 1
                fail(f"CROSSWALK CONFLICT: '{c.id}' {method} served="
                     f"{served} but extracted from the WHO PDF as "
                     f"{phases['I']['category']} (path: "
                     f"{phases['I']['source_path']})")
    notes.append(f"crosswalk agreement: {agree} rating(s) confirmed against "
                 f"the extracted PDF, {conflicts} conflict(s)")
    # WHO prints composites ("2/3", "1,2") where its own guidance is split, and
    # the drug-interaction annex tables that were once parsed through the
    # condition tables' geometry produced nonsense like a barrier category of 3
    # for an antiretroviral. Neither may ever be recorded as a rating, in any
    # state, including the states that are not served.
    for cid, w in cw.items():
        for method, phases in w.get("ratings", {}).items():
            for phase, r in phases.items():
                cat = r.get("category")
                if cat is None:
                    continue
                if not isinstance(cat, int) or isinstance(cat, bool) \
                        or not 1 <= cat <= 4:
                    fail(f"NON-CATEGORICAL RATING: crosswalk records "
                         f"'{cid}'[{method}][{phase}] = {cat!r} "
                         f"(path: {r.get('source_path')!r}); a rating must be a "
                         f"single WHO MEC category 1-4, and a composite must "
                         f"stay unrated")
    # The drug-interaction tables must never be in the extraction output at all.
    raw_path = Path(__file__).resolve().parents[1] / "who_mec_raw.json"
    if raw_path.exists():
        for table, spec in json.loads(
                raw_path.read_text(encoding="utf-8")).items():
            for r in spec.get("rows", []):
                head = r["path"].split(" > ")[0] if " > " in r["path"] else ""
                if head.upper() in DRUG_INTERACTION_SECTIONS:
                    fail(f"CONTAMINATED ROW: table '{table}' still contains a "
                         f"drug-interaction row ({r['path']!r}); it must be "
                         f"excluded because its columns are not the condition "
                         f"table's")
        notes.append(f"extraction contains no drug-interaction rows "
                     f"({len(DRUG_INTERACTION_SECTIONS)} section names barred)")
    unverified = sum(1 for w in cw.values() if w["state"] == "proposed")
    notes.append(f"crosswalk proposals awaiting human review: {unverified} "
                 f"(label equality alone is not proof of identity; none of "
                 f"these are served)")

# --- report ------------------------------------------------------------------
total_cells = len(leaf_ids) * len(ed.METHOD_IDS)
filled = sum(len(c.categories) for c in ed.CONDITIONS)

print("WHO MEC data verification")
print("=" * 60)
print(f"app taxonomy      : {len(app)} nodes "
      f"({len(HEADER_NODES)} headers, {len(leaf_ids)} rated leaf rows)")
print(f"app groups        : {reg['group_count']}")
print(f"backend conditions : {len(ed.CONDITIONS)}")
print(f"staged (not served): {len(ed.PENDING_RATINGS)}")
print(f"golden verified   : {len(GOLDEN)}")
print(f"cells filled      : {filled} / {total_cells} "
      f"({100.0 * filled / total_cells:.1f}%)")
print(f"unrated rows      : {len(leaf_ids) - len(set(ed.CONDITIONS_BY_ID) & leaf_ids)}")

for n in notes:
    print(f"\nnote: {n}")

if failures:
    print(f"\nFAILED ({len(failures)}):")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)

print("\nOK - all invariants hold.")
