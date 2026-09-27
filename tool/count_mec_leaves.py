"""Count true leaf conditions vs parent/branch nodes in the app taxonomy.

WHO MEC assigns a category to leaf rows only. A node like `smoking_35_plus`
is just the "a) Smoker" header above "ii) Age >=35, <15 cig/day" and
"iii) Age >=35, >=15 cig/day" -- it has no category of its own and must not
be rated, or the app would show a fabricated all-clear.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
src = (ROOT / "lib/screens/protection_screen.dart").read_text(encoding="utf-8")

parents = set()
for m in re.finditer(r"ConditionNode\(\s*'([a-z0-9_]+)'", src):
    tail = src[m.end():m.end() + 120]
    if re.match(r"[\s,]*(?:children\s*:)?\s*\[", tail):
        parents.add(m.group(1))

reg = json.loads((ROOT / "mec_registry.json").read_text(encoding="utf-8"))
all_ids = {c["id"] for c in reg["conditions"]}

leaves = all_ids - parents
orphan_parents = parents - all_ids

print(f"nodes in taxonomy   : {len(all_ids)}")
print(f"parent/branch nodes : {len(parents)}")
print(f"TRUE LEAF rows      : {len(leaves)}")
print(f"  (parents not also selectable as leaves: {len(orphan_parents)})")

print("\nParent nodes (must NOT be rated on their own):")
for p in sorted(parents):
    print(f"  {p}")
