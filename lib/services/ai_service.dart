import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/ai_response.dart';
import '../models/health_profile.dart';
import '../services/secure_store.dart';

/// Thrown when there's no valid session to attach to a /chat request
/// (not signed in, or the session expired/was revoked server-side).
/// Callers should catch this separately from a generic network
/// failure so the UI can prompt "please sign in" instead of a vague
/// "couldn't reach the assistant" message.
class AuthRequiredException implements Exception {
  final String message;
  const AuthRequiredException([
    this.message = 'Please sign in to use AI Check-in.',
  ]);

  @override
  String toString() => message;
}

/// Thrown when the request DID reach the server / provider but something
/// failed on the way to a reply: the server's AI provider isn't
/// configured (no GROQ_API_KEY), the provider is busy/rate-limited, a
/// request timed out, or there's no internet. The message is meant to be
/// shown verbatim in the chat screen.
class ChatServerException implements Exception {
  final String message;
  const ChatServerException(this.message);

  @override
  String toString() => message;
}

/// A file/image the user attached to a chat message, sent to the
/// backend as a base64 blob alongside the text. NOTE: the backend's
/// /chat endpoint must be updated to read `attachment` from the
/// request body for the AI to actually "see" this -- see the
/// developer guide. Until then this is delivered but may be ignored
/// server-side.
class ChatAttachment {
  final String fileName;
  final String mimeType;
  final String base64Data;
  const ChatAttachment({
    required this.fileName,
    required this.mimeType,
    required this.base64Data,
  });

  Map<String, dynamic> toJson() => {
    'file_name': fileName,
    'mime_type': mimeType,
    'data_base64': base64Data,
  };
}

class AiService {
  Future<AiResponse> sendMessage({
    required String message,
    required List<ConversationEntry> history,
    Map<String, dynamic>? profileContext,

    /// 'en' or 'ur' -- asks the assistant to reply in that language.
    /// NOTE: the backend must read `language` from the request body
    /// and use it to steer the AI's reply for this to take effect.
    String language = 'en',
    ChatAttachment? attachment,
  }) async {
    // Read from encrypted storage -- the same place CycleProvider and
    // HealthProfileService write the session. (Reading SharedPreferences
    // directly here used to miss the token after the secure-storage
    // migration, so AI Check-in falsely reported "please sign in".)
    final token = await SecureStore.read(SecureStore.tokenKey);
    final expiresMillis = await SecureStore.readExpiryMillis();
    final expired =
        expiresMillis != null &&
        DateTime.fromMillisecondsSinceEpoch(
          expiresMillis,
        ).isBefore(DateTime.now());
    if (token == null || token.isEmpty) {
      throw const AuthRequiredException();
    }
    if (expired) {
      throw const AuthRequiredException(
        'Your session expired. Please sign in again.',
      );
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/chat');

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'message': message,
              'language': language,
              'history': history
                  .map((e) => {'role': e.role, 'message': e.message})
                  .toList(),
              // ignore: use_null_aware_elements
              if (profileContext != null) 'profile_context': profileContext,
              // ignore: use_null_aware_elements
              if (attachment != null) 'attachment': attachment.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const ChatServerException(
        'The assistant took too long to reply. Please try again.',
      );
    } catch (_) {
      throw const ChatServerException(
        "Couldn't reach the AI server. Please check your internet "
        'connection and try again.',
      );
    }

    if (response.statusCode == 401) {
      throw const AuthRequiredException(
        'Your session expired. Please sign in again.',
      );
    }

    if (response.statusCode != 200) {
      // The server sends a short, user-facing `detail` (e.g. "AI assistant
      // isn't configured on this server yet..."). Show it verbatim --
      // previously this was flattened to a generic "couldn't reach the
      // assistant" line that hid the actual cause.
      String detail = '';
      try {
        final parsed = jsonDecode(response.body);
        if (parsed is Map && parsed['detail'] is String) {
          detail = parsed['detail'] as String;
        }
      } catch (_) {
        // Body wasn't JSON -- fall through to the generic message.
      }
      throw ChatServerException(
        detail.isNotEmpty
            ? detail
            : 'The assistant is unavailable right now '
                '(HTTP ${response.statusCode}). Please try again shortly.',
      );
    }

    return AiResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
