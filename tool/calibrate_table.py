import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_who_mec as E
from pypdf import PdfReader

reader = PdfReader(str(E.download()))
first, last = int(sys.argv[1]), int(sys.argv[2])

xs = Counter()
samples = {}
for printed in range(first, last + 1):
    rows = E.baselines(reader.pages[printed + E.PAGE_OFFSET])
    for y in sorted(rows, reverse=True):
        for x, t in rows[y]:
            key = int(x // 10) * 10
            xs[key] += 1
            samples.setdefault(key, []).append((printed, t[:44]))

print(f"pages {first}-{last}: x-clusters (bucket=10pt)\n")
for x, n in sorted(xs.items()):
    s = samples[x][0]
    print(f"  x~{x:<5} n={n:<5} e.g. p{s[0]} {s[1]!r}")
