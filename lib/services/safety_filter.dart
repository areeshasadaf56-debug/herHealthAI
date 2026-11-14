/// safety_filter.dart
///
/// Client-side crisis-signal detection. The backend already returns a
/// `crisis_concern` flag with each AI reply; this is a SECOND, purely
/// local layer that watches the user's own words so the support banner
/// can appear immediately -- without waiting for the server round-trip
/// and even when the request fails.
///
/// Deliberately conservative: a short, explicit phrase list matched on
/// word boundaries. Misses are acceptable (the server's flag and the
/// always-available support resources still catch them); what this
/// design avoids is false positives that hijack an ordinary
/// conversation.
library;

/// Phrases that suggest the writer may be in crisis. Must already be
/// in the exact shape [_normalize] produces: lowercase, single spaces,
/// straight apostrophes. Matched case-insensitively on word
/// boundaries.
const List<String> _crisisPhrases = [
  'kill myself',
  'killing myself',
  'end my life',
  'end it all',
  'suicide',
  'suicidal',
  'self harm',
  'hurt myself',
  'harming myself',
  'want to die',
  "don't want to live",
  'dont want to live',
  'no reason to live',
  'better off without me',
];

/// True when [text] contains a crisis-related phrase. Pure function:
/// safe to call on any input, and empty or blank text simply returns
/// false.
bool containsCrisisSignal(String text) {
  final normalized = _normalize(text);
  if (normalized.isEmpty) return false;

  for (final phrase in _crisisPhrases) {
    final pattern = RegExp('\\b${RegExp.escape(phrase)}\\b');
    if (pattern.hasMatch(normalized)) return true;
  }
  return false;
}

/// Lowercase; hyphens/underscores become spaces (so "self-harm" and
/// "self harm" match alike); curly/backtick apostrophes become
/// straight ones; runs of whitespace collapse to single spaces.
String _normalize(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll(RegExp('[-_]'), ' ');
  t = t.replaceAll(RegExp('[\u2019\u2018`]'), "'");
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t.trim();
}
