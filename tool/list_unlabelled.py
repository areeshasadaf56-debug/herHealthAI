"""List app leaf conditions that have no label, with their group, so the
missing WHO MEC condition headings can be written in context."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
reg = json.loads((ROOT / "mec_registry.json").read_text(encoding="utf-8"))

cur = None
rows = [c for c in reg["conditions"] if not c["label"]]
for c in rows:
    print(f"{c['group'] or '?':<44} {c['id']}")
print(f"\n{len(rows)} missing")
