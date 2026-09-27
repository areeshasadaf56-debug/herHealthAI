import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/ai_response.dart';
import '../models/health_profile.dart';

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

/// A file the user attached to an AI Check-in message.
///
/// Field names must match what the backend reads off the request:
/// `file_name`, `mime_type`, `data_base64` (see `main.py` /`chat.py`).
/// The constructor asserts the same limits the server enforces so an
/// oversized or wrongly-typed file fails with a readable message in the
/// chat bubble instead of a bare 422.
class ChatAttachment {
  /// Server rejects names longer than 255 characters.
  static const int maxFileNameLength = 255;

  /// Server caps decoded uploads at 8 MB.
  static const int maxBytes = 8000000;

  /// The MIME types the server is willing to decode. Anything else is
  /// refused, so catch it here rather than round-tripping a rejected file.
  static const Set<String> allowedMimeTypes = {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain',
  };

  final String fileName;
  final String mimeType;
  final String base64Data;

  ChatAttachment({
    required this.fileName,
    required this.mimeType,
    required this.base64Data,
  }) {
    if (fileName.isEmpty || fileName.length > maxFileNameLength) {
      throw ArgumentError(
        'Attachment name must be between 1 and $maxFileNameLength characters.',
      );
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw ArgumentError('Attachments of type "$mimeType" are not supported.');
    }
    if (base64Data.isEmpty) {
      throw ArgumentError('Attachment is empty.');
    }
  }

  Map<String, dynamic> toJson() => {
    'file_name': fileName,
    'mime_type': mimeType,
    'data_base64': base64Data,
  };
}

class AiService {
  /// The backend caps `history` at 10 entries (`ChatRequest.history` in
  /// `main.py`), and rejects anything longer with a 422. The chat screen hands
  /// us the whole conversation, so without trimming here the seventh turn
  /// would be rejected outright and the chat would stop working.
  static const int maxHistoryEntries = 10;

  /// The backend also caps each history message at 4000 characters.
  static const int maxHistoryMessageChars = 4000;

  /// Trims history to what the server accepts: the most recent
  /// [maxHistoryEntries] entries, each clipped to [maxHistoryMessageChars].
  /// Public and pure so it can be unit-tested against the server's limits.
  static List<Map<String, String>> encodeHistory(
    List<ConversationEntry> history,
  ) {
    final recent = history.length > maxHistoryEntries
        ? history.sublist(history.length - maxHistoryEntries)
        : history;

    return recent.map((e) {
      final text = e.message.length > maxHistoryMessageChars
          ? e.message.substring(0, maxHistoryMessageChars)
          : e.message;
      return <String, String>{'role': e.role, 'message': text};
    }).toList();
  }

  Future<AiResponse> sendMessage({
    required String message,
    required List<ConversationEntry> history,
    Map<String, dynamic>? profileContext,

    /// 'en' or 'ur' -- asks the assistant to reply in that language.
    String language = 'en',
    ChatAttachment? attachment,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken');
    if (token == null) {
      throw const AuthRequiredException();
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/chat');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'message': message,
            'language': language,
            'history': encodeHistory(history),
            // ignore: use_null_aware_elements
            if (profileContext != null) 'profile_context': profileContext,
            // ignore: use_null_aware_elements
            if (attachment != null) 'attachment': attachment.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      throw const AuthRequiredException(
        'Your session expired. Please sign in again.',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Chat request failed (${response.statusCode}): ${response.body}',
      );
    }

    return AiResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
