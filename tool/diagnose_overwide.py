"""Show the baselines that produce over-wide category runs.

y-clustering sometimes merges two visually adjacent table rows into a single
baseline, yielding more values than the table has columns. Those runs are
currently rejected, which loses real rows (including the golden
`migraine_with_aura` row). This prints them in full so the merge pattern can be
identified and split correctly rather than guessed at.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_who_mec as E
from pypdf import PdfReader

reader = PdfReader(str(E.download()))
want = sys.argv[1] if len(sys.argv) > 1 else "chc"

spec = E.TABLES[want]
letters = spec.get("letters", False)
n_cols = spec["n_cols"]
shown = 0

for printed in range(spec["pages"].start, spec["pages"].stop):
    rows = E.baselines(reader.pages[printed + E.PAGE_OFFSET])
    for y in sorted(rows, reverse=True):
        label, cats = E.split_label_and_cats(
            rows[y], spec["cond_max_x"], spec["clarify_min_x"], letters)
        if not cats or not E.is_category_band(cats, letters):
            continue
        if len(cats.split()) <= n_cols:
            continue
        shown += 1
        if shown > 8:
            break
        print(f"--- printed p{printed}  y={y:.1f}  "
              f"{len(cats.split())} values (n_cols={n_cols})")
        print(f"    label: {label!r}")
        print(f"    cats : {cats!r}")
        print("    full : " + " | ".join(
            f"{x:.0f}:{t}" for x, t in sorted(rows[y])))
    if shown > 8:
        break
