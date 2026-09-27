"""Extract WHO MEC 5th edition (2015) category tables from the official PDF.

Source: WHO, "Medical eligibility criteria for contraceptive use", fifth
edition (2015). ISBN 978-92-4-1549152. The document is CC BY-NC-SA 3.0 IGO.

Why coordinates: pypdf's plain extract_text() interleaves the wrapped
condition text with the numeric columns and orphans a large fraction of rows
("3 3 3 3" with no condition). The visitor API exposes x/y per text run, so
clustering by baseline (y) and ordering by x reproduces the real table
geometry and keeps every category attached to its own condition.

Output: who_mec_raw.json -- a faithful, un-normalised dump. Nothing is
guessed, renamed, or merged here; mapping WHO condition text onto the app's
ids is a separate, reviewable step.
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

from pypdf import PdfReader

PDF_URL = "https://afro.who.int/sites/default/files/2017-06/9789241549158_eng.pdf"
CACHE = Path.home() / ".cache" / "who_mec_5e.pdf"
OUT = Path(__file__).resolve().parents[1] / "who_mec_raw.json"

# Printed page -> PDF page index. Front matter is roman numerals; printed
# page 1 is PDF index 6, so index = printed + 5.
PAGE_OFFSET = 5

# Each WHO table has its OWN column geometry, measured with
# `tool/calibrate_table.py` (x-clusters of every text run on the table's
# pages). `cond_max_x` is the right edge of the condition column,
# `clarify_min_x` the left edge of the clarifications/evidence column;
# everything between is the category columns.
#
# `calibrated` is a safety flag, not documentation. It is set True only after
# the table's rows have been checked against hand-verified ratings. An
# uncalibrated table yields incomplete or wrong rows and its output must not be
# promoted into eligibility_data.py.
#
# Every method table except the two sterilization ones splits each method into
# initiation and continuation ("I = initiation, C = continuation" in the table
# header), so it prints TWO values per method. A 4-method table therefore
# yields 8 numbers, not 4:
#     a) Non-migrainous (mild or severe)  1 2 1 2 1 2 1 2
#     ii) with aura, at any age          4 4 4 4 4 4 4 4
# Reading 8 values as "over-wide" and dropping the row loses real data --
# migraine with aura is category 4, and that is one of the app's hand-verified
# golden ratings. `n_cols` is the count of PRINTED values per row and
# `physical` names the method columns left to right, in order.
#
# The sterilization tables are a one-time procedure with no initiation/
# continuation split, so they carry a single A/C/D/S letter.
#
# `cols` remains the app method ids a table feeds, which is a different thing:
# the CHC table has 4 physical columns but only 1 app method id.
TABLES = {
    "chc": dict(pages=range(111, 157), cols=["COC"],
                physical=["COC", "P", "CVR", "CIC"], n_cols=8, init_cont=True,
                calibrated=True, cond_max_x=200.0, clarify_min_x=340.0),
    "pop_poi_impl": dict(pages=range(157, 186), cols=["POP", "DMPA", "Implant"],
                         physical=["POP", "DMPA/NET-EN", "LNG/ETG"], n_cols=6,
                         init_cont=True, calibrated=False, cond_max_x=160.0,
                         clarify_min_x=295.0),
    "iud": dict(pages=range(189, 211), cols=["LNG-IUD", "Cu-IUD"],
                physical=["LNG-IUD", "Cu-IUD"], n_cols=4, init_cont=True,
                calibrated=False, cond_max_x=160.0, clarify_min_x=295.0),
    # One header spanning "Condom Spermicide Diaphragm": 3 methods, 6 values.
    "barr": dict(pages=range(214, 226), cols=["BARR"],
                 physical=["Condom", "Spermicide", "Diaphragm"], n_cols=6,
                 init_cont=True, calibrated=False, cond_max_x=160.0,
                 clarify_min_x=295.0),
    "fem_ster": dict(pages=range(232, 242), cols=["Female sterilization"],
                     physical=["Female sterilization"], n_cols=1,
                     calibrated=False, cond_max_x=160.0,
                     clarify_min_x=285.0, letters=True),
    "male_ster": dict(pages=range(242, 248), cols=["Male sterilization"],
                      physical=["Male sterilization"], n_cols=1,
                      calibrated=False, cond_max_x=160.0,
                      clarify_min_x=295.0, letters=True),
}

# There is deliberately NO "lam" entry. WHO MEC 5th ed contains no
# condition-by-condition eligibility table for the lactational amenorrhoea
# method: its LAM section (printed p229-230) is narrative prose citing the
# Bellagio Consensus, and the only other "LAM" hits in the document are
# incidental words inside unrelated prose. Emitting a 157-row LAM matrix would
# mean inventing every cell, so the tool refuses to. The app must present LAM
# as governed by the Bellagio criteria rather than by condition categories.

# WHO MEC categories are only 1, 2, 3, 4 or NA -- optionally carrying a footnote
# letter ("2A"), or a combination ("1/2", "2+3"). The domain is deliberately
# narrow: page numbers and years also land inside the category x-band, so a
# looser \d+ pattern would happily accept "189" or "2000" as a category.
CAT_TOKEN = re.compile(r"^(NA|[1-4][ABCD]?|[1-4]\s*[/+]\s*[1-4][ABCD]?)$")

# The two sterilization tables do NOT use numbers. They use WHO's sterilization
# legend, printed in the table's own header:
#     "A = accept, C = caution, D = delay, S = special"
# which is WHO's wording for MEC categories 1, 2, 3 and 4. The letters are also
# typeset differently -- inline at the end of the condition run
# ("b) Acute DVT/PE D") or alone on the following baseline -- so a numeric
# matcher can never fire and the tables parse to zero rows.
LETTER_CAT_TOKEN = re.compile(r"^([ACDS])$")
LETTER_TO_CATEGORY = {"A": "1", "C": "2", "D": "3", "S": "4"}


def cat_token(letters):
    """Regex for a valid category token in this table's notation."""
    return LETTER_CAT_TOKEN if letters else CAT_TOKEN


def canonical_categories(raw, letters):
    """Map a row's categories to MEC numbers 1-4/NA, or None if ambiguous.

    Kept separate from extraction so the A/C/D/S -> 1/2/3/4 mapping is one
    auditable step rather than something buried in the parser. Returns None
    rather than a guess: a row that cannot be mapped is dropped downstream.
    """
    out = []
    for tok in raw.split():
        if letters and LETTER_CAT_TOKEN.match(tok):
            out.append(LETTER_TO_CATEGORY[tok])
        elif CAT_TOKEN.match(tok):
            out.append(tok)
        else:
            return None
    return out or None


def split_by_method(values, physical, init_cont):
    """Group a row's flat values into {method: value(s)}.

    A method table prints one value per method, and prints the
    initiation/continuation PAIR only for rows where the two differ. So a
    4-method CHC table yields either:

        "1 1 1 1"        -> every method category 1, no I/C split
        "1 2 1 2 1 2 1 2" -> COC 1/2, P 1/2, CVR 1/2, CIC 1/2

    A single value is reported as {"I": v, "C": v} because an undivided cell
    means WHO rates initiation and continuation identically. Returns None when
    the count matches neither shape -- an unexpected width means the row is
    unreliable and must not be interpreted.
    """
    if not values or not physical:
        return None
    n = len(physical)
    if len(values) == n:
        return {m: {"I": v, "C": v} for m, v in zip(physical, values)}
    if init_cont and len(values) == 2 * n:
        return {m: {"I": values[2 * i], "C": values[2 * i + 1]}
                for i, m in enumerate(physical)}
    return None


def download():
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    if not CACHE.exists():
        print(f"downloading {PDF_URL}", file=sys.stderr)
        req = urllib.request.Request(PDF_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=300) as r:
            CACHE.write_bytes(r.read())
    return CACHE


def baselines(page):
    """Group a page's text runs into visual rows: {y: [(x, text), ...]}."""
    runs = []

    def visit(text, cm, tm, font_dict, font_size):
        t = text.strip()
        if t:
            runs.append((round(tm[5], 1), round(tm[4], 1), t))

    page.extract_text(visitor_text=visit)
    rows = {}
    for y, x, t in runs:
        rows.setdefault(y, []).append((x, t))
    return {y: sorted(cells) for y, cells in rows.items()}


def split_label_and_cats(cells, cond_max_x, clarify_min_x, letters=False):
    """Separate a baseline into (condition label, category tokens, label x).

    `label x` is the left edge of the condition text, which is how indentation is
    detected: WHO prints a parent row flush at x~60 and its sub-rows indented at
    x~68. Only a flush row may become a parent -- otherwise a roman sub-row
    like "i) without aura" is promoted to parent and the next sub-row is
    mislabelled as its child.
    """
    token = cat_token(letters)
    label_parts, cat_parts = [], []
    label_x = None
    for x, t in cells:
        if x >= clarify_min_x:
            continue
        if x < cond_max_x:
            label_parts.append(t)
            label_x = x if label_x is None else min(label_x, x)
        else:
            cat_parts.append(t)

    label = " ".join(label_parts).strip()
    cats = " ".join(cat_parts).strip()

    # Numbers/letters are often typeset inline at the end of the condition run.
    toks = label.split()
    trailing = []
    while toks and token.match(toks[-1]):
        trailing.insert(0, toks.pop())
    if trailing:
        label = " ".join(toks)
        cats = (" ".join(trailing) + " " + cats).strip()

    label = re.sub(r"\s+", " ", label).strip(" †*")
    return label, cats, (label_x if label_x is not None else cond_max_x)


def is_category_band(cats, letters=False):
    """True only if every token is a real WHO MEC category.

    Essential guard: the category x-band also catches running prose, section
    headings and reference fragments. Without this, a held label can be paired
    with whatever text happened to sit to its right -- which silently invents a
    medical rating. Refusing to guess is the correct failure mode.
    """
    toks = cats.split()
    return bool(toks) and all(cat_token(letters).match(t) for t in toks)


ROW_MARKER = re.compile(r"^[a-z0-9]{1,4}[).]\s")

# Section headings carry editorial marks -- "ENDOMETRIAL CANCER*", "CERVICAL
# ECTROPION*", "BREAST DISEASE*" -- so isupper() alone misclassifies them as
# ordinary rows and leaves a stale parent in place.
HEADING = re.compile(r"^[A-Z0-9][A-Z0-9 ,/'()\-\u2013\u2014.]*[*\u2020]?$")

# The column header band is repeated on every page and must never be mistaken
# for a condition, nor become a parent ("CONDITION CATEGORY > BENIGN OVARIAN
# TUMOURS").
HEADER_ROW = re.compile(
    r"^(CONDITION|CATEGORY|CONDITION CATEGORY|CLARIFICATIONS/EVIDENCE"
    r"|METHOD|CHC|POC|IUD|BARR|STANDARD|RECOMMENDATIONS)\b", re.I)


def is_heading(label):
    """True for an ALL-CAPS group heading, ignoring trailing editorial marks."""
    stripped = re.sub(r"[*\u2020]+$", "", label).strip()
    return bool(stripped) and stripped.isupper() and HEADING.match(stripped)


def parse_range(reader, first, last, cond_max_x, clarify_min_x, letters=False,
                n_cols=4, dropped_bad_width=None, indent_x=65.0,
                exact_width=False):
    """Yield (printed_page, path, label, raw_category_text) in document order.

    Layout quirks handled:

    * A row's categories sometimes sit on the baseline *below* its condition
      (the condition column is narrow, so the name wraps). Those rows are
      otherwise orphaned -- losing migraine and breast cancer entirely -- so a
      label with no categories is held and paired with the next
      categories-only baseline.
    * A condition name that itself wraps across baselines is rejoined, so the
      label is not silently truncated mid-phrase.
    * The tables are HIERARCHICAL, and this is what makes crosswalking possible
      at all. An app id like `current_breast_cancer` corresponds to no single
      printed row; it is the parent "d) Breast cancer" plus the sub-row
      "i) current". Both the ALL-CAPS section heading and the unrated parent
      row are therefore tracked and emitted as `path`, so a sub-row is never
      reduced to a bare "i) current" that matches nothing.
    """
    pending = None
    section = ""      # last ALL-CAPS group heading, e.g. "BREAST DISEASE"
    parent = ""       # last unrated parent row, e.g. "d) Breast cancer"
    dropped_bad_width = dropped_bad_width if dropped_bad_width is not None else [0]

    def path_for(label):
        if ROW_MARKER.match(label):
            head = parent or section
        else:
            head = section
        return f"{head} > {label}" if head else label

    for printed in range(first, last):
        idx = printed + PAGE_OFFSET
        if idx >= len(reader.pages):
            continue
        try:
            rows = baselines(reader.pages[idx])
        except Exception as exc:  # a bad page must not kill the run
            print(f"  ! page {printed}: {exc}", file=sys.stderr)
            continue

        ordered = sorted(rows, reverse=True)
        # One baseline of lookahead. A rated row's label often wraps onto the
        # NEXT baseline, which carries no categories of its own:
        #     y570.4  x60:CERVICAL CANCER*   | x217:2 2 2 2
        #     y558.4  x60:(AWAITING TREATMENT)
        # Those two baselines are ONE condition ("cervical cancer, awaiting
        # treatment", category 2). Emitting the first line straight away and
        # leaving the second as an orphan held label with no numbers ships the
        # row under the truncated identity "CERVICAL CANCER", which then
        # collides with every other cervical-cancer row in the app.
        #
        # Rows are buffered in `emitted` so the tail can be folded back into
        # the row above it; document order is preserved when yielding.
        emitted = []
        prev = None  # (label, cats, label_x, y) of the last row-producing baseline
        for y in ordered:
            label, cats, label_x = split_label_and_cats(
                rows[y], cond_max_x, clarify_min_x, letters)

            # A label-only baseline directly below a rated row is that row's
            # wrapped tail, not a new condition. WHO's own geometry decides it:
            # measured across these tables, a wrapped continuation sits 12.0pt
            # below the line it continues (normal leading), while a genuinely
            # separate row or section heading sits 18.5pt below (row pitch).
            # Using the gap rather than capitalisation matters, because a tail
            # can be all-caps too -- "CERVICAL INTRAEPITHELIAL" wraps to
            # "NEOPLASIA (CIN)", which a heading test would wrongly reject and
            # which would then ship as a truncated identity.
            if (emitted and label and not cats and prev
                    and prev[0] and prev[1] and is_category_band(prev[1], letters)
                    and 0 < prev[3] - y <= 13.0
                    and abs(label_x - prev[2]) <= 2
                    and not ROW_MARKER.match(label)):
                p_page, p_path, p_label, p_cats = emitted[-1]
                merged = f"{p_label} {label}".strip()
                # The crosswalk matches on `path`, not on the bare condition
                # text, so the leaf of the path has to grow too. Rebuild it by
                # swapping the old leaf for the merged one and keeping the
                # section/parent prefix intact -- the tail belongs to the leaf,
                # it does not become a parent of anything.
                if ">" in p_path:
                    prefix = p_path.rsplit(">", 1)[0]
                    p_path = f"{prefix}> {merged}"
                else:
                    p_path = merged
                emitted[-1] = (p_page, p_path, merged, p_cats)
                prev = (label, cats, label_x, y)
                continue

            # WHO uses one typesetting grid for every table: a parent row is
            # flush at x~60 and its sub-rows are indented at x~68. The gap is
            # only ~8pt, so the threshold is absolute -- deriving it from
            # cond_max_x (200*0.85) puts it at 170 and flags nothing.
            indented = label_x >= indent_x
            if not label:
                # categories-only baseline: belongs to the held label, but only
                # if what sits in the band really is a category row
                if cats and pending and is_category_band(cats, letters):
                    width = len(cats.split())
                    ok = (width == n_cols) if exact_width else (width <= n_cols)
                    if ok:
                        emitted.append(
                            (pending[0], path_for(pending[1]), pending[1], cats))
                    else:
                        dropped_bad_width[0] += 1
                    pending = None
                prev = (label, cats, label_x, y)
                continue
            if not cats:
                # possible wrapped tail of the held label, or a new label
                # whose numbers are on the next baseline
                if pending and not ROW_MARKER.match(label) \
                        and not is_heading(label):
                    pending = (pending[0], f"{pending[1]} {label}".strip())
                else:
                    # an unrated flush marker row is a parent for the sub-rows
                    # below; an indented row is itself a sub-row and must not
                    # displace the parent
                    if is_heading(label) and not ROW_MARKER.match(label):
                        section, parent = label, ""
                    elif ROW_MARKER.match(label) and not indented:
                        parent = label
                    pending = (printed, label)
                prev = (label, cats, label_x, y)
                continue
            if is_category_band(cats, letters):
                # Width guard. A method table prints one value per method, and
                # prints the initiation/continuation PAIR only for rows where
                # the two differ -- so a 4-method CHC table legitimately yields
                # either 4 or 8 values (measured: 123 rows at 4, 7 at 8). Only
                # MORE than 2 x methods is a merge artifact from y-clustering,
                # and rejecting it is the safe direction: a dropped row can be
                # re-derived, a silently merged one ships a fabricated rating.
                # `exact_width` exists for callers that know better than the
                # width heuristic and want a strict full-width match.
                width = len(cats.split())
                ok = (width == n_cols) if exact_width else (width <= n_cols)
                if HEADER_ROW.match(label):
                    pass
                elif ok:
                    # A rated ALL-CAPS row is itself a top-level condition (e.g.
                    # "ENDOMETRIAL CANCER* 1 1 1 1"), so it is its own section
                    # and must not inherit the previous one as a parent.
                    if is_heading(label) and not ROW_MARKER.match(label):
                        section, parent = label, ""
                        path = label
                    else:
                        path = path_for(label)
                    emitted.append((printed, path, label, cats))
                else:
                    dropped_bad_width[0] += 1
                pending = None
            else:
                # prose in the band: not a table row
                pending = None
            prev = (label, cats, label_x, y)

        for row in emitted:
            yield row


# Sections that are NOT condition rows. WHO MEC 5e tacks a set of drug
# interaction tables onto the end of the CHC, POP/PA/IM, IUD and barrier
# annexes. They list antiretroviral drugs, anticonvulsants, antimicrobials and
# latex allergy rather than user conditions, and they are printed with their own
# column layout, so parsing them with the condition table's geometry invents
# numbers. These are the literal headings as printed, so this list is auditable
# rather than a heuristic.
#
# "CONDITION CATEGORY" is deliberately NOT here. It looks like a running head but
# also carries genuine conditions in several tables -- for example the IUD table's
# "c) Immunosuppressive treatment" and "a) Current purulent cervicitis" -- so
# dropping it would discard real rows.
DRUG_INTERACTION_SECTIONS = frozenset({
    "ANTIRETROVIRAL THERAPY",
    "ANTIRETROVIRAL THERAPY (ART)",
    "ANTICONVULSANT THERAPY",
    "ANTIMICROBIAL THERAPY",
    "ALLERGY TO LATEX",
    # Running head of the barrier table, which bleeds into the row beneath it on
    # the final page and wrongly becomes the parent of a drug name.
    "BARRIER METHODS (BARR)",
})


def main():
    reader = PdfReader(str(download()))
    out = {}
    total_dropped_sections = 0
    for table, spec in TABLES.items():
        note = "" if spec["calibrated"] else "  [UNCALIBRATED - do not trust]"
        print(f"parsing {table}{note} ...", file=sys.stderr)
        letters = spec.get("letters", False)
        rows = []
        kept = []
        dropped = [0]
        dropped_sections = []
        for printed, path, label, cats in parse_range(
                reader, spec["pages"].start, spec["pages"].stop,
                spec["cond_max_x"], spec["clarify_min_x"], letters,
                spec["n_cols"], dropped, 65.0, False):
            # WHO MEC 5e appends a set of drug-interaction tables to the end of
            # the CHC, POP/PA/IM, IUD and barrier annexes. They are printed with
            # a different column layout, so reading them through the condition
            # table's geometry invents numbers. It produced a barrier category of
            # 3 (delay) for Raltegravir, where WHO rates every ART drug as
            # usable with barrier methods, and 2/3 composites for IUDs. These
            # sections are named, not guessed at, and are dropped rather than
            # read with the wrong columns.
            head = path.split(" > ")[0] if " > " in path else ""
            if head.upper() in DRUG_INTERACTION_SECTIONS:
                dropped_sections.append((printed, path))
                continue
            canon = canonical_categories(cats, letters)
            kept.append({"page": printed, "path": path, "condition": label,
                         "raw": cats, "canonical": canon,
                         "by_method": split_by_method(
                             canon, spec.get("physical"),
                             spec.get("init_cont", False))})
        rows = kept
        total_dropped_sections += len(dropped_sections)
        out[table] = {"cols": spec["cols"], "physical": spec.get("physical"),
                      "init_cont": spec.get("init_cont", False),
                      "calibrated": spec["calibrated"],
                      "letters": letters, "dropped_bad_width": dropped[0],
                      "dropped_drug_interaction_sections": len(dropped_sections),
                      "rows": rows}
        print(f"  {len(rows)} candidate rows"
              + (f" ({dropped[0]} rejected as over-wide)" if dropped[0] else "")
              + (f" ({len(dropped_sections)} dropped: drug-interaction table, "
                 f"wrong columns)" if dropped_sections else ""),
              file=sys.stderr)

    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {OUT} ({total_dropped_sections} drug-interaction rows "
          f"excluded)", file=sys.stderr)
    trusted = [t for t, s in out.items() if s["calibrated"]]
    print(f"total candidate rows: {sum(len(t['rows']) for t in out.values())}")
    print(f"geometry-verified tables: {', '.join(trusted) or 'none'}")


if __name__ == "__main__":
    main()
