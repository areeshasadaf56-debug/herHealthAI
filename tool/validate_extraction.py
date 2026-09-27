"""Validate the extracted WHO rows against the hand-verified golden ratings.

If the pipeline cannot reproduce ratings a human already checked against the
official tables, it must not be trusted for the other 1,400 cells.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
raw = json.loads((ROOT / "who_mec_raw.json").read_text(encoding="utf-8"))

chc = [(r["page"], r["condition"], r["raw"]) for r in raw["chc"]["rows"]]

PROBES = [
    ("vte_current (CHC 4)",                r"Acute DVT/PE",              4),
    ("vte_history (CHC 4)",                r"History of DVT/PE",         4),
    ("migraine_with_aura (CHC 4)",         r"migraine",                  4),
    ("hypertension_elevated_160_plus (4)",  r"160\s*/\s*100",            4),
    ("current_breast_cancer (CHC 4)",       r"Current breast cancer",     4),
    ("cirrhosis_severe (CHC 4)",            r"[Dd]ecompensated",          4),
    ("breastfeeding_lt6weeks (CHC 4)",      r"<\s*6 weeks postpartum",     4),
    ("obesity_bmi30 (CHC 2)",               r"30 kg/m2 BMI",              2),
    ("smoking_35+ <15cig (CHC 3)",          r"<\s*15 cigarettes",         3),
    ("smoking_35+ 15+cig (CHC 4)",          r"15 cigarettes",             4),
]

print(f"{'probe':<38} {'expect':>6}  found rows")
print("-" * 100)
ok = bad = 0
for name, pat, expect in PROBES:
    hits = [(p, c, r) for p, c, r in chc if re.search(pat, c, re.I)]
    if not hits:
        print(f"{name:<38} {expect:>6}  *** NOT FOUND ***")
        bad += 1
        continue
    for p, c, r in hits[:4]:
        first = r.split()[0]
        mark = "ok " if first == str(expect) else "MISMATCH"
        if first == str(expect):
            ok += 1
        else:
            bad += 1
        print(f"{name:<38} {expect:>6}  {mark} p{p} {c[:40]!r} -> {r[:30]!r}")
    print()

print(f"matched={ok}  problems={bad}")
