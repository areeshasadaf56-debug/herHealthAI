"""Audit the backend's WHO MEC condition IDs against the Flutter app taxonomy.

Finds:
  * backend condition IDs the app can never select (orphans)
  * app condition IDs with no backend entry (uncovered)
  * app condition IDs with no local fallback label (would render as raw ids
    if the API ever returned them without a label)
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT.parent / "pcos_ml_project" / "app_backend" / "eligibility_data.py"

reg = json.loads((ROOT / "mec_registry.json").read_text(encoding="utf-8"))
app = {c["id"]: c for c in reg["conditions"]}

src = BACKEND.read_text(encoding="utf-8")
block = src[src.index("CONDITIONS: list[ConditionEntry]"):]
entries = re.findall(
    r'ConditionEntry\(\s*\n?\s*"([a-z0-9_]+)"', block)

orphans = [i for i in entries if i not in app]
covered = [i for i in entries if i in app]
uncovered = [i for i in app if i not in entries]
unlabelled = [i for i in app if not app[i]["label"]]

print(f"app conditions          : {len(app)}")
print(f"backend conditions      : {len(entries)}")
print(f"  usable by the app     : {len(covered)}")
print(f"  ORPHANED (app can't   : {len(orphans)}")
print(f"   ever select these)")
print(f"app NOT in backend      : {len(uncovered)}")
print(f"app with no local label : {len(unlabelled)}")

if orphans:
    print("\nORPHANED backend ids (backend id  ->  closest app id):")
    for o in orphans:
        guess = min(app, key=lambda a: abs(len(a) - len(o)) +
                    sum(x != y for x, y in zip(a, o)))
        print(f"  {o:<42} ~ {guess}")

if uncovered:
    print("\nUNCOVERED app ids:")
    for i in uncovered:
        print(f"  {i}")
