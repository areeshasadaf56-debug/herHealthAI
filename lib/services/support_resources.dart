/// support_resources.dart
///
/// The external crisis-support resources the app links to from the AI
/// check-in's crisis banner (task 4.4). This list is deliberately
/// SHORT: every entry must be real and verified before it ships. An
/// invented or wrong helpline here is worse than a missing one,
/// because someone in crisis may act on it.
library;

/// One tappable support resource shown with the crisis banner.
class SupportResource {
  /// The row's text. Must be a string that already exists in
  /// urdu_string.dart so the existing translation is reused instead of
  /// inventing new claims or translations.
  final String label;

  /// Where the link opens. HTTPS only.
  final String url;

  const SupportResource({required this.label, required this.url});
}

/// Resources shown alongside the crisis banner.
/// // OWNER: add the vetted local crisis lines for each launch market
/// here (verified URL or helpline number only -- never an invented
/// one).
const List<SupportResource> kCrisisSupportResources = [
  SupportResource(
    label:
        'Befrienders Worldwide (befrienders.org) lists crisis lines by '
        'country.',
    url: 'https://www.befrienders.org',
  ),
];
