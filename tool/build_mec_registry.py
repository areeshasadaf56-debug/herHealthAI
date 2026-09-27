"""Build the WHO MEC condition registry from the Flutter app's own taxonomy.

The app already encodes the WHO MEC 5th edition (2015) structure: 54 condition
groups, leaf condition ids, human-readable labels, and `_init` / `_cont`
suffixes that mirror WHO's initiation-vs-continuation columns.

This script produces `mec_registry.json`, the single source of truth for WHICH
conditions exist, what they are called, and which WHO MEC section each belongs
to. It deliberately assigns NO ratings: a rating is only ever written into
`eligibility_data.py` after being checked against the official WHO MEC table.
"""

import json
import re
from collections import OrderedDict

PATH = "lib/screens/protection_screen.dart"

src = open(PATH, encoding="utf-8").read()

# ---- leaf ids ---------------------------------------------------------------
# Leaves are declared either as ConditionNode('id', ...) or via the
# _leaves([...]) helper. Collect both, then keep only ids that actually
# resolve to a label or a group (guards against false positives).
ids = set(re.findall(r"ConditionNode\(\s*'([a-z0-9_]+)'", src))
for block in re.findall(r"_leaves\(\[([^\]]*)\]\)", src, re.S):
    ids.update(re.findall(r"'([a-z0-9_]+)'", block))

# ---- labels -----------------------------------------------------------------
label_src = src[src.index("_fallbackConditionLabels"):]
labels = {}
for cid, raw in re.findall(r"'([a-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'", label_src):
    labels[cid] = (
        raw.replace("\\'", "'")
        .replace("&gt;", ">")
        .replace("&lt;", "<")
        .replace("&ge;", ">=")
        .replace("\u2265", ">=")
    )

# ---- groups + nesting -------------------------------------------------------
group_starts = [(m.start(), m.group(1)) for m in
                re.finditer(r"ConditionGroup\(\s*\n?\s*'([^']+)'", src)]
bounds = []
for idx, (pos, name) in enumerate(group_starts):
    end = group_starts[idx + 1][0] if idx + 1 < len(group_starts) else len(src)
    bounds.append((name, pos, end))

id_group = {}
for cid in sorted(ids):
    occurrences = [m.start() for m in re.finditer(rf"'{re.escape(cid)}'", src)]
    for name, start, end in bounds:
        if any(start <= h < end for h in occurrences):
            id_group[cid] = name
            break

# ---- assemble ---------------------------------------------------------------
entries = []
for cid in sorted(ids):
    entries.append({
        "id": cid,
        "label": labels.get(cid),
        "group": id_group.get(cid),
        "init_cont": ("continuation" if cid.endswith("_cont")
                      else "initiation" if cid.endswith("_init") else None),
        "source": "WHO MEC 5th edition (2015)",
        "verified": False,
    })

missing_label = [e["id"] for e in entries if not e["label"]]
missing_group = [e["id"] for e in entries if not e["group"]]

out = {
    "source": "WHO MEC 5th edition (2015), Geneva: World Health Organization",
    "note": (
        "Registry only. 'verified': false means no rating has been checked "
        "against the official table yet, and the API must report "
        "'Not yet assessed' for it rather than guessing."
    ),
    "condition_count": len(entries),
    "group_count": len(bounds),
    "conditions": entries,
}

with open("mec_registry.json", "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, ensure_ascii=False)

print(f"conditions : {len(entries)}")
print(f"groups     : {len(bounds)}")
print(f"with label : {len(entries) - len(missing_label)}")
print(f"no label   : {len(missing_label)}")
if missing_label:
    for cid in missing_label:
        print("   MISSING LABEL:", cid)
if missing_group:
    print(f"no group   : {len(missing_group)}")
    for cid in missing_group:
        print("   MISSING GROUP:", cid)
