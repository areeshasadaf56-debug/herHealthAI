"""Extract the app's full WHO MEC condition id list from protection_screen.dart.

The ids are a structured taxonomy (anticonvulsant_certain, art_abacavir_init,
...). This script only *extracts* them; it does not assign any ratings.
"""
import json
import re
import sys

PATH = "lib/screens/protection_screen.dart"

src = open(PATH, encoding="utf-8").read()

# Every explicit ConditionNode('id', ...) / ConditionNode('id')
nodes = re.findall(r"ConditionNode\(\s*'([a-z0-9_]+)'", src)

# _leaves(['a', 'b', ...]) helper used for flat groups
leaf_ids = []
for block in re.findall(r"_leaves\(\[([^\]]*)\]\)", src, re.S):
    leaf_ids += re.findall(r"'([a-z0-9_]+)'", block)

ids = sorted(set(nodes) | set(leaf_ids))

# Group names, so we can sanity-check the taxonomy
groups = re.findall(r"ConditionGroup\(\s*\n?\s*'([^']+)'", src)

out = {
    "count": len(ids),
    "ids": ids,
    "group_count": len(set(groups)),
    "groups": sorted(set(groups)),
}

with open("condition_ids.json", "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2)

print(f"unique condition ids : {len(ids)}")
print(f"condition groups     : {len(set(groups))}")
print()
for i in range(0, len(ids), 6):
    print("  " + "  ".join(f"{x:<34}" for x in ids[i:i + 6]).rstrip())
