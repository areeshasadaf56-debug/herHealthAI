"""Crosswalk WHO MEC 5th ed. rows -> the app's condition ids.

This is the step that turns `who_mec_raw.json` into something the backend can
serve, and it is the step most likely to produce silently wrong medical advice
if it is done loosely. Two rules govern everything here:

1. WHO text is never rewritten into a rating by inference. A rating is only
   ever copied from the extracted `by_method` cell -- never recomputed or
   guessed.
2. Anything not established is reported, not served. Every app id lands in
   exactly one state, and every state records HOW it was established:
     verified    - hand-checked against the printed WHO page (GOLDEN below)
     extracted   - matched mechanically at high confidence, PENDING REVIEW
     needs_review- ambiguous; candidates are listed, nothing is served
     unmapped    - no WHO row located

   `extracted` is deliberately not called `auto`/`accept`. The distinction
   that matters to a user reading the app is "a clinician checked this" vs
   "a script matched this", and that difference is carried all the way
   through to the Flutter UI.

Method mapping (WHO physical column -> app method id) is explicit below. Note
that the app's `chc` describes pill/patch/ring, while WHO's CHC table has a
fourth column, CIC (combined injectable contraceptive), which the app does not
offer; CIC is therefore excluded rather than silently folded in.

Run:  python tool/crosswalk.py
Writes mec_crosswalk.json and prints a coverage summary.
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mec_text import (AUTO_THRESHOLD, context_of, leaf_of, norm,  # noqa: E402
                      score, strip_phase, tokens)

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "who_mec_raw.json"
REGISTRY = ROOT / "mec_registry.json"
OUT = ROOT / "mec_crosswalk.json"

# app method id -> (source table, list of WHO physical columns to consider)
# "worst" keeps the highest (most restrictive) category across the columns.
METHOD_SOURCES = {
    "chc":      ("chc", ["COC", "P", "CVR"]),          # CIC deliberately excluded
    "pop":      ("pop_poi_impl", ["POP"]),
    "poi":      ("pop_poi_impl", ["DMPA/NET-EN"]),
    "impl":     ("pop_poi_impl", ["LNG/ETG"]),
    "lng_iud":  ("iud", ["LNG-IUD"]),
    "cu_iud":   ("iud", ["Cu-IUD"]),
    "barrier":  ("barr", ["Condom", "Spermicide", "Diaphragm"]),
    "fem_ster": ("fem_ster", ["Female sterilization"]),
    "male_ster": ("male_ster", ["Male sterilization"]),
    # "lam": WHO MEC 5th ed has no condition-by-condition LAM table at all.
    # Its LAM section is narrative prose citing the Bellagio Consensus, so
    # there is nothing to crosswalk and nothing may be invented.
}

# Methods whose table splits initiation and continuation. The app carries 32
# conditions as separate *_init / *_cont ids, so the phase has to be chosen
# per condition rather than assumed.
INIT_CONT_METHODS = {"chc", "pop", "poi", "impl", "lng_iud", "cu_iud", "barrier"}

# Categories are ordered by restrictiveness: the highest number wins.
CAT_RANK = {"NA": 0, "1": 1, "2": 2, "3": 3, "4": 4}


# Group headings in the app taxonomy. WHO MEC gives categories to leaf rows
# only; rating a class heading such as "Protease inhibitors (PIs)" fabricates an
# all-clear for a category the source never assigned. `smoking_35_plus` is not
# a WHO class heading but behaves like one: WHO rates only its two
# cigarettes-per-day sub-rows, so the parent has no category of its own.
# tool/verify_mec_data.py enforces this independently; the two lists agreeing
# is deliberate.
HEADER_NODES = {
    "art_integrase", "art_nnrti", "art_nrti", "art_pi",
    "breast_cancer_category", "smoking_35_plus",
}


def category_for(row, method_id, phase):
    """Highest category across the WHO columns backing this app method.

    A value is only usable if it is a single WHO MEC category 1-4. WHO also
    prints composites ("2/3", "1,2") where its own guidance is split; picking
    either half would be inventing a category, so those cells are skipped and
    the method is simply left unrated. CAT_RANK.get(val, 0) would have silently
    scored them 0 and let a composite through as the best value.
    """
    _, cols = METHOD_SOURCES[method_id]
    by = row.get("by_method") or {}
    best, seen = None, []
    for col in cols:
        cell = by.get(col)
        if not cell:
            continue
        val = cell.get(phase) if isinstance(cell, dict) else cell
        if val is None:
            continue
        seen.append(val)
        if not re.fullmatch(r"[1-4]", str(val).strip()):
            continue
        val = int(str(val).strip())
        if best is None or CAT_RANK.get(val, 0) > CAT_RANK.get(best, 0):
            best = val
    return (best, seen) if best is not None else (None, seen)


def phases_for(cond):
    """Which initiation/continuation phases apply to this app condition."""
    ic = cond.get("init_cont")
    if ic == "initiation":
        return ["I"]
    if ic == "continuation":
        return ["C"]
    return ["I", "C"]


# Placeholder the extractor emits when it could not identify a real section
# heading. It carries no information and must never be treated as a mismatch.
PLACEHOLDER_SECTIONS = {"condition category", "condition", "category"}


def _is_genuine_section(element):
    """A real section heading is printed in ALL CAPS by WHO.

    This distinction matters: in `d) Breast cancer > i) current` the first
    element is a parent row, not a section, and the extractor's section
    tracking is lost across some page breaks entirely. Comparing an app group
    against a parent row produces a false mismatch and silently rejects good
    matches, so only ALL-CAPS elements are treated as sections.
    """
    e = element.strip()
    if not e or not any(c.isalpha() for c in e):
        return False
    if norm(e) in PLACEHOLDER_SECTIONS:
        return False
    return e == e.upper()


def family(cid):
    """Collapse a condition's phase variants to a single identity.

    The app ships `endometrial_cancer` alongside
    `endometrial_cancer_initiation` and `endometrial_cancer_continuation`, and
    WHO prints one row for all three. They are not competing claims on that row,
    they are the same condition read at different phases, so the collision
    guard must see one claimant. Without this the guard flagged 23 sound
    conditions and served none of them.
    """
    return re.sub(r"_(init|cont|initiation|continuation)$", "", cid)


def section_agrees(app_group, who_path):
    """Does the WHO row sit in a section that plausibly matches the app group?

    This is the guard against the p120 failure: the smoking sub-rows sit
    directly beneath "b) Migraine" and are parented under it, so a short app
    label ("Age >= 35") can match a WHO row belonging to a different condition.
    Where the app states a group and the WHO row's real ALL-CAPS section shares
    no vocabulary with it, the match is not trusted.

    Returns True / False / None, where None means "no usable section
    information" and the match is judged on label evidence alone.
    """
    g = tokens(app_group)
    if not g:
        return None
    sections = [e for e in who_path.split(">")[:-1] if _is_genuine_section(e)]
    if not sections:
        return None  # section lost by the extractor; do not invent a verdict
    st = set()
    for s in sections:
        st |= tokens(s)
    return bool(g & st)


def main():
    raw = json.loads(RAW.read_text(encoding="utf-8"))
    reg = json.loads(REGISTRY.read_text(encoding="utf-8"))

    # Candidate pool per table. Rows whose width could not be interpreted
    # (by_method is null) are excluded: a category we cannot read is not a
    # category we may serve. Normalised labels and tokens are precomputed once
    # because the scan below is O(conditions x rows).
    pool = {}
    for table, spec in raw.items():
        # A heading is anything that has children in this table. WHO prints most
        # section headings in ALL CAPS, but it also prints genuine
        # single-condition rows that way ("EPILEPSY", "STROKE", "ASTHMA"), so
        # capitals alone cannot tell them apart. Being a parent can.
        #
        # This matters: treating the heading "BLOOD PRESSURE" as a rateable
        # condition collapsed five unrelated app conditions onto
        # "d) Vascular disease" and shared one category between them.
        parents = set()
        for row in spec["rows"]:
            parts = [p.strip() for p in row["path"].split(">")]
            parents.update(parts[:-1])
        entries = []
        for row in spec["rows"]:
            if not row.get("by_method"):
                continue
            leaf = leaf_of(row["path"])
            if leaf in parents:
                continue
            entries.append((row, leaf, norm(leaf), tokens(leaf)))
        pool[table] = entries

    results, counts = [], {"verified": 0, "extracted": 0, "needs_review": 0,
                           "unmapped": 0}
    for cond in reg["conditions"]:
        cid, label = cond["id"], cond["label"]
        # The app appends "/ Initiation" or " - continuation" to 32 labels and
        # WHO never prints it, so the phase is stripped before matching and
        # re-applied from phases_for() when the rating is read.
        target = norm(strip_phase(label))
        target_tokens = tokens(label)
        entry = {"id": cid, "label": label, "group": cond["group"],
                 "init_cont": cond.get("init_cont"), "state": "unmapped",
                 "ratings": {}, "candidates": []}
        if cid in HEADER_NODES:
            # Never rate a group heading, whatever the labels look like.
            results.append(entry)
            continue

        for method_id in METHOD_SOURCES:
            want_table = METHOD_SOURCES[method_id][0]
            phase_bests = {}
            phase_ambiguous = set()
            for row, leaf, nleaf, ltok in pool.get(want_table, []):
                # Cheap prefilter before the scoring work: a match must share a
                # content word with the app label.
                if target_tokens and ltok and not (target_tokens & ltok):
                    continue
                s, why = score(label, leaf)
                if s < AUTO_THRESHOLD:
                    continue
                agrees = section_agrees(cond["group"], row["path"])
                # An EXACT leaf match is direct identity evidence, and section
                # context must not overrule it. WHO's section names and the
                # app's group names frequently use different words for the same
                # thing -- app "Varicose veins" against WHO "SUPERFICIAL VENOUS
                # DISORDERS", app "ART" against WHO "BARRIER METHODS (BARR)" --
                # so "shares no word" is missing evidence, not evidence of a
                # mismatch, and vetoing on it silently dropped sound conditions.
                # The veto still applies to weaker containment/fuzzy matches,
                # which is what it was written for (the p120 smoking rows).
                trust = (min(s, 0.5)
                         if agrees is False and why != "exact" else s)
                for phase in phases_for(cond):
                    cat, _ = category_for(row, method_id, phase)
                    if cat is None:
                        continue
                    prev = phase_bests.get(phase)
                    if prev is None or trust > prev[0]:
                        phase_bests[phase] = (trust, cat, why, row["path"],
                                              agrees)
                    elif trust == prev[0] and prev[3] != row["path"]:
                        # Two genuinely different WHO rows match this condition
                        # equally well. Picking one would be a coin flip on
                        # medical guidance, so it is held for review instead.
                        phase_ambiguous.add(phase)
            for phase, (trust, cat, why, path, agrees) in phase_bests.items():
                entry["ratings"].setdefault(method_id, {})[phase] = {
                    "category": cat, "source_path": path, "table": want_table,
                    "match": why, "score": round(trust, 3),
                    "section_agrees": agrees,
                }
                if phase in phase_ambiguous:
                    entry["state"] = "needs_review"
                    entry["candidates"].append(
                        {"method": method_id, "phase": phase,
                         "category": cat, "source_path": path,
                         "match": why, "score": round(trust, 3),
                         "section_agrees": agrees,
                         "reason": ("more than one WHO row matches this "
                                    "condition equally well")})
                elif trust < AUTO_THRESHOLD:
                    entry["state"] = "needs_review"
                    entry["candidates"].append(
                        {"method": method_id, "phase": phase,
                         "category": cat, "source_path": path,
                         "match": why, "score": round(trust, 3),
                         "section_agrees": agrees,
                         "reason": ("section context disagrees with the app "
                                    "group" if agrees is False and why != "exact"
                                    else "match too weak to auto-serve")})

        if entry["ratings"] and entry["state"] != "needs_review":
            # `extracted`, not `auto`: label equality (or containment after
            # phase/parenthesis normalisation) is strong evidence, but it is a
            # script's conclusion, not a clinician's. It is served only with
            # that provenance attached, all the way to the UI.
            entry["state"] = "extracted"
        results.append(entry)

    # Golden overrides: hand-checked against the printed WHO tables. These are
    # the only rows promoted without further review.
    GOLDEN = {
        "vte_current": {"chc": "4", "iud": "2", "barrier": "1"},
        "vte_history": {"chc": "4", "iud": "2", "barrier": "1"},
        "migraine_with_aura": {"chc": "4", "iud": "2", "barrier": "1"},
        "hypertension_elevated_160_plus": {"chc": "4", "iud": "1", "barrier": "1"},
        "current_breast_cancer": {"chc": "4", "iud": "1", "barrier": "1"},
        "cirrhosis_severe": {"chc": "4", "iud": "3", "barrier": "1"},
        "breastfeeding_lt6weeks": {"chc": "4", "iud": "2", "barrier": "1"},
        "obesity_bmi30": {"chc": "2", "iud": "1", "barrier": "1"},
        "smoking_35_plus_under15cig": {"chc": "3", "iud": "1", "barrier": "1"},
        "smoking_35_plus_15plus_cig": {"chc": "4", "iud": "1", "barrier": "1"},
    }
    # ---- collision guard -------------------------------------------------
    # Two DIFFERENT conditions resolving to the same WHO row means at least one
    # identity is wrong, and the categories would then be silently shared. That
    # is demoted to needs_review rather than served on a guess.
    #
    # Identity is the condition's own text, not its id string. The app ships
    # several rows that are the same condition written twice:
    #   cervical_cancer / _initiation / _continuation, and
    #   cervical_cancer_awaiting_treatment / _initiation / _continuation
    # all carry the label "Cervical cancer (awaiting treatment)". Keying on the
    # id called that a collision and served none of the six, even though they
    # describe one WHO row and one set of categories. Keying on the
    # phase-stripped, normalised label collapses them to a single identity,
    # which is what they are.
    #
    # The key MUST include the table: the same path text is printed in several
    # tables ("EPILEPSY" appears in chc, iud, barr, fem_ster and male_ster as
    # five physically different rows). Keying on the path alone flagged those
    # as collisions and wrongly demoted 33 sound conditions.
    claimants = {}
    for entry in results:
        identity = norm(strip_phase(entry["label"]))
        for phases in entry["ratings"].values():
            for phase in phases.values():
                path = phase.get("source_path")
                if path and path != "GOLDEN":
                    claimants.setdefault((phase.get("table"), path),
                                         set()).add(identity)
    collisions = {k for k, ids in claimants.items() if len(ids) > 1}
    if collisions:
        for entry in results:
            hit = {(ph.get("table"), ph.get("source_path"))
                   for phases in entry["ratings"].values()
                   for ph in phases.values()} & collisions
            if hit:
                entry["state"] = "needs_review"
                entry["candidates"].append(
                    {"reason": "WHO row also claimed by another condition",
                     "source_rows": sorted(f"{t}: {p}" for t, p in hit)})

    by_id = {r["id"]: r for r in results}
    for cid, expect in GOLDEN.items():
        if cid not in by_id:
            print(f"  ! golden id not in registry: {cid}", file=sys.stderr)
            continue
        entry = by_id[cid]
        entry["state"] = "verified"
        # Stored as int, not the digit string used in the GOLDEN literal, so the
        # whole crosswalk has one representation of a category. A rating is
        # always a single int 1-4; a composite such as "2/3" is never a rating
        # and the validator now enforces that across every state.
        entry["ratings"] = {
            m: {"I": {"category": int(v), "source_path": "GOLDEN",
                      "match": "hand", "score": 1.0, "section_agrees": None},
                "C": {"category": int(v), "source_path": "GOLDEN",
                      "match": "hand", "score": 1.0, "section_agrees": None}}
            for m, v in expect.items()}

    for entry in results:
        counts[entry["state"]] = counts.get(entry["state"], 0) + 1

    OUT.write_text(json.dumps(
        {"source": "WHO MEC 5th edition (2015), ISBN 978-92-4-1549152",
         "method_sources": {k: list(v) for k, v in METHOD_SOURCES.items()},
         "note": ("lam is absent by design: WHO MEC 5th ed has no "
                  "condition-by-condition table for it."),
         "provenance": {
             "verified": "hand-checked against the printed WHO page",
             "extracted": "matched mechanically; PENDING clinical review",
             "needs_review": "ambiguous match; not served",
             "unmapped": "no WHO row located; not served",
         },
         "counts": counts, "conditions": results},
        indent=1, ensure_ascii=False), encoding="utf-8")

    total = len(results)
    print(f"wrote {OUT}")
    for state in ("verified", "extracted", "needs_review", "unmapped"):
        print(f"  {state:<13} {counts.get(state, 0):4}  "
              f"({counts.get(state, 0) * 100.0 / total:.1f}%)")
    cells = sum(len(r["ratings"]) for r in results)
    served = sum(1 for r in results
                 if r["state"] in ("verified", "extracted"))
    print(f"  servable conditions           : {served}/{total}")
    print(f"  method entries produced       : {cells}")
    print("\n'verified' and 'extracted' may be served; every extracted rating "
          "keeps its provenance so the UI can label it as pending review.")

    # The app taxonomy states some conditions more than once (the same label
    # under several ids, usually a base row plus phase variants). That is not a
    # mapping problem and does not block serving, but it does mean the user sees
    # the same condition listed several times, so it is worth surfacing.
    dupes = {}
    for entry in results:
        dupes.setdefault(norm(strip_phase(entry["label"])), []).append(
            entry["id"])
    # A label group whose ids all collapse to one family is just a phase pair
    # ("X_init" / "X_cont" and their shared label) -- expected, not a defect.
    # Only groups spanning more than one family are genuine duplication.
    dupes = {k: v for k, v in dupes.items()
             if len({family(i) for i in v}) > 1}
    if dupes:
        print(f"\n{len(dupes)} condition(s) appear under ids from more than one "
              f"family with the same label -- review the app taxonomy:")
        for label, ids in sorted(dupes.items()):
            print(f"  {', '.join(sorted(ids))}")


if __name__ == "__main__":
    main()
