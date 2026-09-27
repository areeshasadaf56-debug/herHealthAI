"""Shared text utilities for matching app condition labels to WHO MEC rows.

Kept in one place because two tools depend on the exact same normalisation:
`crosswalk.py` (which produces served data) and `propose_mappings.py` (the
review diagnostic). If the two ever disagreed, the diagnostic would stop
being a valid picture of what the crosswalk actually did.

The single most important function here is `strip_phase`. The app appends the
initiation/continuation phase to 32 of its own labels -- sometimes as
" / Initiation", sometimes as an em dash -- and WHO never prints it. Without
stripping it, none of those 32 conditions can ever match.
"""
import difflib
import re

MARKER = re.compile(r"^[a-z]{1,2}[0-9]{0,2}[).]\s*")
FOOTNOTE = re.compile(r"[*\u2020]")
PAREN = re.compile(r"\([^)]*\)")
IC_SUFFIX = re.compile(r"\s*[/\u2014\u2013-]\s*(initiation|continuation)\s*$",
                       re.IGNORECASE)

STOP = {
    "a", "an", "and", "the", "of", "in", "on", "or", "to", "for", "with",
    "without", "at", "age", "years", "year", "i", "ii", "iii", "iv", "v",
}


def strip_phase(label):
    """Remove a trailing ' / Initiation' or ' - continuation' style suffix."""
    cleaned = IC_SUFFIX.sub("", (label or "").strip()).strip()
    return cleaned or (label or "").strip()


def norm(text):
    """Normalize a label for comparison: drop WHO's a)/ii) markers, fold case."""
    t = MARKER.sub("", (text or "").strip())
    t = FOOTNOTE.sub("", t)
    t = t.replace("\u2265", ">=").replace("\u2264", "<=")
    t = re.sub(r"[^a-z0-9<>=/%\s-]", " ", t.lower())
    return re.sub(r"\s+", " ", t).strip()


def tokens(text):
    return {w for w in norm(text).split() if w and w not in STOP}


def leaf_of(path):
    """The most specific printed label in a hierarchical path."""
    return path.split(">")[-1].strip()


def context_of(path):
    """Section + parent, i.e. everything before the leaf."""
    return " > ".join(p.strip() for p in path.split(">")[:-1])


# Minimum score for an automatic match. Containment and parenthesis-stripping
# both score above fuzzy token overlap, so a curated alias is never needed for
# a difference that is purely presentational.
AUTO_THRESHOLD = 0.92


# Words that invert the clinical meaning of a condition. These must match on
# both sides or the labels are NOT describing the same thing.
#
# This guard exists because containment matching is direction-agnostic, and
# without it "Postpartum, not breastfeeding" matched the WHO row
# "i) breastfeeding" -- which is the opposite clinical state and would have
# inverted the advice (not breastfeeding is the higher-risk category).
NEGATION = {"not", "no", "without", "excluding"}


def negations(text):
    return NEGATION & tokens(text)


def score(app_label, who_label):
    """Confidence that an app label denotes the same condition as a WHO label.

    Returns (score, reason). `reason` is always printed next to a suggestion so
    a reviewer can judge the match rather than trusting the number:
      exact     - identical after normalisation (and phase stripping)
      paren     - identical once explanatory parentheses are removed
      contains  - one label contains the other, so WHO simply prints it shorter
      negation  - one side negates and the other does not; REJECTED
      tok/seq   - fuzzy overlap only; NOT safe to auto-accept
    """
    if negations(app_label) != negations(who_label):
        return 0.4, "negation"

    a, w = norm(strip_phase(app_label)), norm(strip_phase(who_label))
    if a == w:
        return 1.0, "exact"

    a2, w2 = norm(PAREN.sub(" ", a)), norm(PAREN.sub(" ", w))
    if a2 and w2 and a2 == w2:
        return 0.98, "paren"
    # WHO often prints the bare condition while the app adds an example
    # ("Certain anticonvulsants" vs "Certain anticonvulsants (e.g. phenytoin)").
    if a2 and w2 and min(len(a2), len(w2)) >= 8 and (a2 in w2 or w2 in a2):
        return 0.93, "contains"

    ta, tw = tokens(app_label), tokens(who_label)
    if not ta or not tw:
        return 0.0, "none"
    tok = len(ta & tw) / len(ta | tw)
    seq = difflib.SequenceMatcher(None, a, w).ratio()
    return max(tok, seq * 0.95), ("tok" if tok >= seq else "seq")
