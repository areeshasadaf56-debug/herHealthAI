"""Diagnostic: for every unmapped app condition, show the closest WHO rows.

`tool/crosswalk.py` only accepts an exact normalized-label match, which leaves
126 of 162 app ids unmapped. This tool does NOT change any served data. It
prints, per unmapped app id, the WHO leaf labels that fuzzy/token matching
ranks highest, so the mapping can be written as an explicit, reviewable table
instead of guessed at runtime.

Scoring is deliberately conservative and printed alongside every suggestion so
a reviewer can judge it: `exact` is label equality, `tok` is token overlap, and
`seq` is difflib ratio. Suggestions are candidates for a human, never ratings.

Run:  python tool/propose_mappings.py [--table chc] [--only id1,id2]
"""
import argparse
import difflib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "who_mec_raw.json"
REG = ROOT / "mec_registry.json"
XWALK = ROOT / "mec_crosswalk.json"

MARKER = re.compile(r"^[a-z]{1,2}[0-9]{0,2}[).]\s*")
FOOTNOTE = re.compile(r"[*\u2020]")

STOP = {
    "a", "an", "and", "the", "of", "in", "on", "or", "to", "for", "with",
    "without", "at", "age", "years", "year", "i", "ii", "iii", "iv", "v",
}

# The app appends the phase to its own label -- both as a slash and as an em
# dash, inconsistently across the 32 init/cont pairs. WHO never prints it, so
# it has to come off before the labels can be compared at all.
IC_SUFFIX = re.compile(r"\s*[/\u2014\u2013-]\s*(initiation|continuation)\s*$",
                       re.IGNORECASE)


def strip_phase(label):
    return IC_SUFFIX.sub("", (label or "").strip()).strip() or (label or "")


def norm(text):
    t = MARKER.sub("", (text or "").strip())
    t = FOOTNOTE.sub("", t)
    t = t.replace("\u2265", ">=").replace("\u2264", "<=")
    t = re.sub(r"[^a-z0-9<>=/%\s-]", " ", t.lower())
    return re.sub(r"\s+", " ", t).strip()


def leaf_of(path):
    return path.split(">")[-1].strip()


def context_of(path):
    return " > ".join(p.strip() for p in path.split(">")[:-1])


def tokens(text):
    return {w for w in norm(text).split() if w and w not in STOP}


PAREN = re.compile(r"\([^)]*\)")


def score(app_label, who_label):
    a, w = norm(strip_phase(app_label)), norm(strip_phase(who_label))
    if a == w:
        return 1.0, "exact"
    # WHO often prints the bare condition while the app adds an explanatory
    # parenthetical ("Certain anticonvulsants" vs "Certain anticonvulsants
    # (e.g. phenytoin, ...)"), or vice versa. Stripping parentheses and
    # accepting containment recovers those without any hand-written alias.
    a2, w2 = norm(PAREN.sub(" ", a)), norm(PAREN.sub(" ", w))
    if a2 and w2 and (a2 == w2):
        return 0.98, "paren"
    if a2 and w2 and min(len(a2), len(w2)) >= 8:
        if a2 in w2 or w2 in a2:
            return 0.93, "contains"
    ta, tw = tokens(app_label), tokens(who_label)
    if not ta or not tw:
        return 0.0, "none"
    inter = ta & tw
    tok = len(inter) / len(ta | tw)
    seq = difflib.SequenceMatcher(None, a, w).ratio()
    return max(tok, seq * 0.95), ("tok" if tok >= seq else "seq")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", default=None)
    ap.add_argument("--only", default=None)
    ap.add_argument("--min", type=float, default=0.45)
    ap.add_argument("--top", type=int, default=3)
    args = ap.parse_args()

    raw = json.loads(RAW.read_text(encoding="utf-8"))
    reg = json.loads(REG.read_text(encoding="utf-8"))
    xw = {c["id"]: c for c in json.loads(XWALK.read_text(encoding="utf-8"))["conditions"]}

    tables = {args.table} if args.table else set(raw)
    leaves = []
    for table, spec in raw.items():
        if table not in tables:
            continue
        for row in spec["rows"]:
            if not row.get("by_method"):
                continue  # uninterpretable width -> not a usable candidate
            leaves.append((table, row["path"], leaf_of(row["path"])))

    wanted = set(args.only.split(",")) if args.only else None
    shown = 0
    for cond in reg["conditions"]:
        cid = cond["id"]
        if wanted and cid not in wanted:
            continue
        if xw[cid]["state"] in ("verified", "proposed"):
            continue
        cands = []
        for table, path, leaf in leaves:
            s, how = score(cond["label"], leaf)
            if s >= args.min:
                cands.append((s, how, table, path))
        cands.sort(reverse=True)
        shown += 1
        head = f"{cid}  [{cond['group']}]"
        if not cands:
            print(f"\n{head}\n    label: {cond['label']}\n    -- no candidate >= {args.min}")
            continue
        print(f"\n{head}\n    label: {cond['label']}")
        for s, how, table, path in cands[:args.top]:
            print(f"    {s:.2f} {how:<5} [{table}] {path}")
    print(f"\n{shown} unmapped conditions examined "
          f"(tables: {', '.join(sorted(tables))})")


if __name__ == "__main__":
    main()
