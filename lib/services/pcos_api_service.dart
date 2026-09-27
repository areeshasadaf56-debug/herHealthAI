import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Handles communication with the FastAPI PCOS backend.
class PcosApiService {
  static String get _baseUrl => ApiConfig.baseUrl;

  /// Sends the form data to the /predict endpoint and returns the parsed result.
  ///
  /// Throws an [Exception] with a user-friendly message if the request fails
  /// or the server returns an error.
  static Future<PcosResult> predict({
    required double ageYrs,
    required double weightKg,
    required double heightCm,
    required String cycleRegularity, // 'Regular' or 'Irregular'
    required double cycleLengthDays,
    required double prl,
    required double vitD3,
    required double prg,
    required double rbs,
    required double bpSystolic,
    required double bpDiastolic,
    required double follicleNoL,
    required double follicleNoR,
    required double avgFSizeL,
    required double avgFSizeR,
    required double endometrium,
    required String weightGain, // 'Yes' or 'No'
    required String hairGrowth,
    required String skinDarkening,
    required String hairLoss,
    required String pimples,
    required String fastFood,
    required String regularExercise,
  }) async {
    final uri = Uri.parse('$_baseUrl/predict');

    final body = jsonEncode({
      "age_yrs": ageYrs,
      "weight_kg": weightKg,
      "height_cm": heightCm,
      "cycle_regularity": cycleRegularity,
      "cycle_length_days": cycleLengthDays,
      "prl": prl,
      "vit_d3": vitD3,
      "prg": prg,
      "rbs": rbs,
      "bp_systolic": bpSystolic,
      "bp_diastolic": bpDiastolic,
      "follicle_no_l": follicleNoL,
      "follicle_no_r": follicleNoR,
      "avg_f_size_l": avgFSizeL,
      "avg_f_size_r": avgFSizeR,
      "endometrium": endometrium,
      "weight_gain": weightGain,
      "hair_growth": hairGrowth,
      "skin_darkening": skinDarkening,
      "hair_loss": hairLoss,
      "pimples": pimples,
      "fast_food": fastFood,
      "regular_exercise": regularExercise,
    });

    http.Response response;

    try {
      response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 30));
    } on http.ClientException {
      throw Exception(
        'Could not reach the server right now. Please try again shortly.',
      );
    } catch (e) {
      throw Exception('Request timed out or failed: $e');
    }

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PcosResult.fromJson(data);
      } catch (e) {
        throw Exception('Server responded, but the data could not be read: $e');
      }
    } else {
      throw Exception(
        'Server error (${response.statusCode}): ${response.body}',
      );
    }
  }
}

/// Parsed response from the /predict endpoint.
class PcosResult {
  final String prediction;
  final double pcosProbability;
  final String modelUsed;

  /// Screening band: 'low', 'elevated', or 'high'.
  ///
  /// A single 0.5 cutoff misses about 1 in 4 real cases, so the backend
  /// reports a band as well. The fields are optional because an older
  /// deployment may not send them; [riskLevel] then falls back to a value
  /// derived from the probability so the UI still behaves sensibly.
  final String? riskLevel;
  final String? riskLabel;
  final String? screeningAdvice;

  PcosResult({
    required this.prediction,
    required this.pcosProbability,
    required this.modelUsed,
    this.riskLevel,
    this.riskLabel,
    this.screeningAdvice,
  });

  /// Effective band, derived locally when the server did not supply one.
  String get effectiveRiskLevel {
    if (riskLevel != null) return riskLevel!;
    if (pcosProbability >= 0.5) return 'high';
    if (pcosProbability >= 0.35) return 'elevated';
    return 'low';
  }

  String get effectiveRiskLabel =>
      riskLabel ?? _defaultLabelFor(effectiveRiskLevel);

  String get effectiveScreeningAdvice =>
      screeningAdvice ?? _defaultAdviceFor(effectiveRiskLevel);

  static String _defaultLabelFor(String level) {
    switch (level) {
      case 'high':
        return 'High likelihood';
      case 'elevated':
        return 'Possible - worth screening';
      default:
        return 'Low likelihood';
    }
  }

  static String _defaultAdviceFor(String level) {
    switch (level) {
      case 'high':
        return 'Your answers are strongly associated with PCOS. Please arrange '
            'an appointment with a doctor for proper testing and confirmation.';
      case 'elevated':
        return 'Some of your answers are associated with PCOS. This is not a '
            'diagnosis, but it is worth discussing with a doctor.';
      default:
        return 'Your answers do not strongly suggest PCOS. Keep tracking your '
            'cycle and symptoms, and see a doctor if they change.';
    }
  }

  factory PcosResult.fromJson(Map<String, dynamic> json) {
    return PcosResult(
      prediction: json['prediction'] as String? ?? 'Unknown',
      pcosProbability: (json['pcos_probability'] as num?)?.toDouble() ?? 0.0,
      modelUsed: json['model_used'] as String? ?? 'Unknown model',
      riskLevel: json['risk_level'] as String?,
      riskLabel: json['risk_label'] as String?,
      screeningAdvice: json['screening_advice'] as String?,
    );
  }
}
