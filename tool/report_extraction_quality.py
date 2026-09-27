"""Data-quality report for who_mec_raw.json.

Extraction that is silently wrong is worse than extraction that is missing, so
this reports the ways the raw output is known to be imperfect before anyone
tries to crosswalk it onto app ids.
"""
import json
import re
from collections import Counter
from pathlib import Path

RAW = Path(__file__).resolve().parents[1] / "who_mec_raw.json"

raw = json.loads(RAW.read_text(encoding="utf-8"))
total_dupes = 0
for table, spec in raw.items():
    rows = spec["rows"]
    norm = [re.sub(r"\W+", " ", r["condition"].lower()).strip() for r in rows]
    counts = Counter(norm)
    dupes = {k: v for k, v in counts.items() if v > 1}
    # A label ending mid-phrase: unbalanced bracket, or a dangling connector.
    # Row markers like "a)" must be stripped first, otherwise every single row
    # looks unbalanced and the metric reports ~90 false positives per table.
    marker = re.compile(r"^[a-z0-9]{1,4}[).]\s*")
    dangling = re.compile(r"\b(and|or|of|with|the|to|for|in)\s*$", re.I)
    trunc = [r for r in rows
             if marker.sub("", r["condition"]).count("(")
             != marker.sub("", r["condition"]).count(")")
             or dangling.search(marker.sub("", r["condition"]))]
    no_rating = [r for r in rows if not r["canonical"]]
    pages = [r["page"] for r in rows]
    total_dupes += len(dupes)

    print(f"{table:14} rows={len(rows):4} pages={min(pages) if pages else 0}-"
          f"{max(pages) if pages else 0:<4} dupes={len(dupes):3} "
          f"truncated={len(trunc):3} unmappable={len(no_rating):3} "
          f"calibrated={spec['calibrated']}")
    for k in list(dupes)[:3]:
        where = sorted({r["page"] for r in rows
                        if re.sub(r"\W+", " ", r["condition"].lower()).strip() == k})
        print(f"      dupe x{counts[k]}: {k[:52]!r} on pages {where}")
    for r in trunc[:2]:
        print(f"      trunc: {r['condition'][:52]!r}")

print(f"\ntotal duplicate labels across tables: {total_dupes}")
