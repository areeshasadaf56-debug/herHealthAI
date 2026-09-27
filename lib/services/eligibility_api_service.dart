import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// MODULE: services/eligibility_api_service.dart
/// ROLE: Talks to the FastAPI backend's contraceptive-eligibility endpoints
/// (GET /conditions, GET /methods_reference, GET /effectiveness,
/// POST /eligibility). Used by screens/protection_screen.dart to power
/// the Eligibility tool.
/// The service reads the shared ApiConfig.baseUrl value so all API
/// clients use the same environment-specific backend.

/// A single selectable medical condition, as returned by GET /conditions.
class Condition {
  final String id;
  final String label;

  /// Whether a clinician has checked this condition's WHO MEC ratings
  /// against the printed source. 'hand_verified' means a person confirmed
  /// them; 'extracted_pending_review' means they were matched from the PDF
  /// automatically and still need that sign-off. Anything else is unknown to
  /// the client, so it is treated as unreviewed rather than trusted.
  final String provenance;

  /// True only for ratings a human has actually checked.
  bool get isClinicallyVerified => provenance == 'hand_verified';

  Condition({
    required this.id,
    required this.label,
    this.provenance = 'extracted_pending_review',
  });

  factory Condition.fromJson(Map<String, dynamic> json) {
    return Condition(
      id: json['id'] as String,
      label: json['label'] as String,
      provenance: json['provenance'] as String? ?? 'extracted_pending_review',
    );
  }
}

/// A single contraceptive method, as returned by GET /methods_reference.
class MethodInfo {
  final String id;
  final String label;

  MethodInfo({required this.id, required this.label});

  factory MethodInfo.fromJson(Map<String, dynamic> json) {
    return MethodInfo(id: json['id'] as String, label: json['label'] as String);
  }
}

/// The eligibility result for one method, as returned by POST /eligibility.
class MethodResult {
  final String methodLabel;

  /// WHO MEC category 1-4, or null when the backend has no verified
  /// rating for this method given the selected conditions. The backend
  /// deliberately returns null rather than guessing a category, so this
  /// must stay nullable -- see eligibility_data.check_eligibility.
  final int? category;

  /// Explanation shown when [category] is null ("not yet assessed"), or when
  /// the rating is only machine-matched and still awaits a clinician.
  final String? note;

  /// True when a machine-extracted, unreviewed condition contributed to this
  /// result. The category is still WHO's own number, but the reader is
  /// entitled to know a clinician has not signed it off.
  final bool pendingReview;

  /// False when the backend did not send the WHO MEC audit field
  /// (`pending_review`) for this result.
  ///
  /// The reviewed backend always sends it, and returns `category: null` with
  /// a note for anything it has not verified. The older build still deployed
  /// at the PythonAnywhere host answers *every* condition with a flat
  /// `category: 1` across all nine methods and no note at all, so a missing
  /// audit field means the number is not WHO's guidance and must never be
  /// presented as an all-clear. It is flagged rather than trusted.
  final bool serverAudited;

  /// True when this result must carry a caveat, either because a human has
  /// not signed off the rating or because the server is not the reviewed
  /// build. Screens use this to decide whether to show the review banner.
  bool get needsCaveat => pendingReview || !serverAudited;

  /// Shown when the server gave a number without saying where it came from.
  static const String unverifiedNote =
      'This rating came from a backend that does not report its WHO MEC '
      'review status, so it has not been checked against the source. '
      'Confirm with a qualified provider before relying on it.';

  MethodResult({
    required this.methodLabel,
    required this.category,
    this.note,
    this.pendingReview = false,
    this.serverAudited = true,
  });

  factory MethodResult.fromJson(Map<String, dynamic> json) {
    final audited = json.containsKey('pending_review');
    final pending = json['pending_review'] as bool? ?? false;
    final serverNote = json['note'] as String?;
    return MethodResult(
      // Tolerant rather than a hard cast: a wrong-shaped server should
      // produce a flagged row, not an unhandled TypeError in a health app.
      methodLabel: (json['method_label'] as String?) ?? 'Unknown method',
      category: (json['category'] as num?)?.toInt(),
      note: serverNote ?? (audited ? null : unverifiedNote),
      pendingReview: pending || !audited,
      serverAudited: audited,
    );
  }
}

/// One row of the effectiveness comparison, as returned by GET /effectiveness.
class EffectivenessEntry {
  final String method;
  final num typicalUseFailurePercent;
  final String? note;

  EffectivenessEntry({
    required this.method,
    required this.typicalUseFailurePercent,
    this.note,
  });

  factory EffectivenessEntry.fromJson(Map<String, dynamic> json) {
    return EffectivenessEntry(
      method: json['method'] as String,
      typicalUseFailurePercent: json['typical_use_failure_percent'] as num,
      note: json['note'] as String?,
    );
  }
}

/// Turns a non-2xx response into an Exception WITHOUT ever throwing.
///
/// The backend answers handled errors with JSON `{"detail": ...}`, but an
/// unhandled server error replies with a plain-text body (uvicorn returns
/// bare `Internal Server Error`), and a proxy or CDN in between can return
/// an HTML error page. Decoding the body unconditionally threw a
/// FormatException in those cases, which replaced the real HTTP status with
/// a decoding error -- so the actual server failure could never be seen or
/// reported. Decode defensively and always keep the status code.
Exception _apiError(String what, http.Response response) {
  final status = response.statusCode;
  String detail = '';
  try {
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['detail'] != null) {
      detail = decoded['detail'].toString();
    }
  } on FormatException {
    // Not JSON (plain text / HTML / empty). Fall back to the raw body below.
  }
  if (detail.isEmpty) {
    detail = response.body.trim();
    if (detail.length > 160) detail = '${detail.substring(0, 160)}...';
  }
  return Exception(
    detail.isEmpty
        ? '$what failed ($status)'
        : '$what failed ($status): $detail',
  );
}

class EligibilityApiService {
  /// Overridable base URL. Defaults to [ApiConfig.baseUrl] so production
  /// behaviour is unchanged, but tests can point this at a local server
  /// that returns a deliberately malformed error body -- the failure that
  /// used to throw a FormatException and hide the real status code.
  final String baseUrl;

  /// Injectable so tests can exercise the real parsing path against a
  /// scripted response, including the un-audited backend described on
  /// [MethodResult.serverAudited].
  final http.Client _client;

  EligibilityApiService({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  Future<List<Condition>> fetchConditions() async {
    final response = await _client.get(Uri.parse('$baseUrl/conditions'));
    if (response.statusCode != 200) {
      throw _apiError('Loading conditions', response);
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => Condition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MethodInfo>> fetchMethodsReference() async {
    final response = await _client.get(Uri.parse('$baseUrl/methods_reference'));
    if (response.statusCode != 200) {
      throw _apiError('Loading methods', response);
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => MethodInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EffectivenessEntry>> fetchEffectiveness() async {
    final response = await _client.get(Uri.parse('$baseUrl/effectiveness'));
    if (response.statusCode != 200) {
      throw _apiError('Loading effectiveness data', response);
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => EffectivenessEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MethodResult>> checkEligibility(List<String> conditionIds) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/eligibility'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'condition_ids': conditionIds}),
    );
    if (response.statusCode != 200) {
      throw _apiError('Eligibility check', response);
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => MethodResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
