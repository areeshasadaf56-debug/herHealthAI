import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:file_picker/file_picker.dart';
import '../l10n/app_text.dart';
import '../l10n/language_provider.dart';
import '../theme/app_theme.dart';
import '../models/health_profile.dart';
import '../providers/cycle_provider.dart';
import '../services/health_profile_service.dart';
import '../services/ai_service.dart';
import '../services/chat_nav_hints.dart';
import '../services/chat_profile_updates.dart';
import 'health_diary_screen.dart';
import 'sign_in_screen.dart';

// ---- Claude-inspired look for this screen only (warm paper + terracotta).
// Deliberately local constants so the rest of the app keeps its rose theme.
const Color _cBg = Color(0xFFFAF9F5); // warm cream "paper" background
const Color _cClay = Color(0xFFC96442); // terracotta accent (send, links)
const Color _cClaySoft = Color(0xFFFBEFE7); // soft clay tint
const Color _cUserBubble = Color(0xFFF0EEE5); // user turn bubble
const Color _cText = Color(0xFF20201E); // near-black body text
const Color _cMuted = Color(0xFF8A8781); // secondary gray
const Color _cBorder = Color(0xFFE7E3DA); // hairline border
const Color _cWhite = Color(0xFFFFFFFF);

class _ChatSession {
  final String sessionId;
  final List<ConversationEntry> entries;
  _ChatSession(this.sessionId, this.entries);

  DateTime get lastActivity => entries.last.timestamp;

  String get title {
    final firstUser = entries.firstWhere(
      (e) => e.role == 'user',
      orElse: () => entries.first,
    );
    final text = firstUser.message.trim();
    if (text.isEmpty) return 'New chat';
    return text.length > 40 ? '${text.substring(0, 40)}…' : text;
  }
}

class AiCheckinScreen extends StatefulWidget {
  final void Function(String tabName)? onNavigateToTab;

  const AiCheckinScreen({super.key, this.onNavigateToTab});

  @override
  State<AiCheckinScreen> createState() => _AiCheckinScreenState();
}

class _AiCheckinScreenState extends State<AiCheckinScreen> {
  final HealthProfileService _profileService = HealthProfileService();
  final AiService _aiService = AiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  HealthProfile? _profile;
  final List<ConversationEntry> _messages = [];
  String _currentSessionId = '';
  bool _loading = true;
  bool _sending = false;
  bool _showCrisisBanner = false;
  bool _showMedicalEmergencyBanner = false;
  // Suggestion banner shown above the input ("Take me to PCOS / Endo / Diary").
  ChatNavHint? _navHint;
  String? _errorText;
  bool _needsSignIn = false;

  /// True right after a send failed, so the "Retry" affordance appears
  /// and the user's text + attachment (restored into the input) can be
  /// sent again without retyping (task 1.7).
  bool _sendFailed = false;

  // --- Language ---
  // Derived from the app-wide LanguageProvider (the fixed "EN | اردو"
  // pill at the top of every screen) instead of a separate in-screen
  // toggle. One switch now controls the whole app AND what language
  // Saheli replies in; the class name is kept because the language
  // flag is threaded through many screen methods below.
  String _language = 'en';

  // --- Voice input (speech-to-text) ---
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  // --- File/image attachment ---
  PlatformFile? _pendingAttachment;
  bool _pickingFile = false;

  // --- Enter-to-send on desktop/web ---
  final FocusNode _inputFocusNode = FocusNode();

  static const _openingGreeting =
      "Hi -- I'm here to check in on how you've really been. Take your "
      "time, there's no rush. How have you been feeling lately, overall?";

  static const _openingGreetingUr =
      'سلام -- میں یہ جاننے اِس لیے آئی ہوں کہ آج آپ حال میں واقعی کیسے '
      'محسوس کر رہی ہیں۔ آرام سے، کوئی جلدی نہیں۔ آپ حال ہی میں مجموعی '
      'طور پر کیسا محسوس کر رہی ہیں؟';

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    _initSpeech();
    // Live profile updates: a diary entry saved in the Health Diary or
    // a privacy toggle flipped in Data & Privacy reaches this tab (even
    // while it's parked behind the shell's IndexedStack) through the
    // service's shared notifier.
    _profileService.profileUpdated.addListener(_onExternalProfileUpdate);
  }

  void _onExternalProfileUpdate() {
    if (!mounted) return;
    final updated = _profileService.profileUpdated.value;
    if (updated == null) return;
    if (_profile == null || updated.userId != _profile!.userId) {
      return; // no doc yet / another account's document
    }
    // Chat messages are independent in-memory state and are NOT reset
    // here -- only the profile document the updates/privacy come from.
    setState(() => _profile = updated);
  }

  @override
  void dispose() {
    _profileService.profileUpdated.removeListener(_onExternalProfileUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    if (_listening) _speech.stop();
    super.dispose();
  }

  /// Sets up the 2speech recognizer. On Flutter web this uses the
  /// browser's built-in Web Speech API -- it works in Chrome/Edge but
  /// isn't supported in every browser, hence the availability check.
  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _errorText = 'Voice input error: ${err.errorMsg}';
        });
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          setState(() => _listening = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      setState(
        () => _errorText =
            'Voice input isn\'t available in this browser. Try Chrome or Edge.',
      );
      return;
    }

    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    setState(() {
      _listening = true;
      _errorText = null;
    });

    await _speech.listen(
      localeId: _language == 'ur' ? 'ur_PK' : 'en_US',
      onResult: (result) {
        setState(() {
          // Live-update the text field as words are recognized; final
          // punctuation/casing cleanup is left to the user before send.
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        });
      },
    );
  }

  /// Opens the file/image picker and stages the result as a pending
  /// attachment shown above the input bar (sent along with the next
  /// message, or removable before then).
  Future<void> _pickAttachment() async {
    if (_pickingFile) return;
    setState(() => _pickingFile = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
          'gif',
          'webp',
          'pdf',
          'doc',
          'docx',
          'txt',
        ],
        withData: true, // needed on web to get raw bytes
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) {
        setState(() => _errorText = 'Could not read that file. Try again.');
        return;
      }
      // Keep uploads reasonably small -- large base64 payloads can time
      // out the /chat request or exceed the backend's body-size limit.
      const maxBytes = 8 * 1024 * 1024; // 8 MB
      if (file.bytes!.length > maxBytes) {
        setState(() => _errorText = '${file.name} is too large (max 8 MB).');
        return;
      }
      setState(() {
        _pendingAttachment = file;
        _errorText = null;
      });
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  void _removeAttachment() {
    setState(() => _pendingAttachment = null);
  }

  String _mimeTypeFor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'text/plain';
    }
  }

  List<_ChatSession> _sessionsFrom(HealthProfile p) {
    final grouped = <String, List<ConversationEntry>>{};
    for (final e in p.conversationLog) {
      final key = e.sessionId ?? 'legacy';
      grouped.putIfAbsent(key, () => []).add(e);
    }
    final sessions = grouped.entries
        .map((e) => _ChatSession(e.key, e.value))
        .toList();
    sessions.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return sessions;
  }

  Future<void> _loadInitialState() async {
    final profile = await _profileService.loadProfile();
    if (!mounted) return;

    final sessions = _sessionsFrom(profile);
    setState(() {
      _profile = profile;
      if (sessions.isNotEmpty) {
        _currentSessionId = sessions.first.sessionId;
        _messages.addAll(sessions.first.entries);
      } else {
        _startFreshSession();
      }
      _loading = false;
    });
  }

  void _startFreshSession() {
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _messages.clear();
    _messages.add(
      ConversationEntry(
        timestamp: DateTime.now(),
        role: 'assistant',
        message: LanguageProvider.urdu ? _openingGreetingUr : _openingGreeting,
        sessionId: _currentSessionId,
      ),
    );
    _navHint = null;
    _showCrisisBanner = false;
    _showMedicalEmergencyBanner = false;
  }

  void _startNewChat() {
    setState(_startFreshSession);
  }

  /// Bottom sheet with the AI privacy toggles (AI can read my diary /
  /// AI remembers past conversations). Same profile settings as
  /// Settings > Data & Privacy, surfaced in-screen because this is where
  /// chat behavior changes when they're flipped off.
  void _openPrivacySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PrivacySheet(
        initialProfile: _profile!,
        service: _profileService,
        onProfileUpdated: (updated) {
          if (!mounted) return;
          setState(() => _profile = updated);
        },
      ),
    );
  }

  void _openHistory() {
    final sessions = _sessionsFrom(_profile!);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr('Chats'),
                        style: AppTextStyles.sans(
                          size: 16,
                          weight: FontWeight.w700,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _startNewChat();
                        },
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 16, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(
                              tr('New chat'),
                              style: AppTextStyles.sans(
                                size: 13,
                                weight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: sessions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            tr('No past chats yet.'),
                            style: AppTextStyles.sans(
                              size: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final s = sessions[index];
                            final isActive = s.sessionId == _currentSessionId;
                            return ListTile(
                              onTap: () {
                                Navigator.pop(sheetContext);
                                setState(() {
                                  _currentSessionId = s.sessionId;
                                  _messages
                                    ..clear()
                                    ..addAll(s.entries);
                                  _navHint = null;
                                });
                              },
                              leading: Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              title: Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.sans(
                                  size: 13,
                                  weight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                _formatDate(s.lastActivity),
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final attachment = _pendingAttachment;
    if ((text.isEmpty && attachment == null) || _sending) return;

    _inputController.clear();
    setState(() {
      _sending = true;
      _errorText = null;
      _needsSignIn = false;
      _sendFailed = false;
      _navHint = null;
      _pendingAttachment = null;
    });

    // Live privacy at send time: the profile the request is built from
    // is the latest COMMITTED one, so a toggle flipped while an earlier
    // turn was in flight takes effect on this very message instead of
    // one message late (task 1.4).
    final committedProfile = _profileService.profileUpdated.value;
    if (committedProfile != null &&
        committedProfile.userId == (_profile?.userId ?? '')) {
      _profile = committedProfile;
    }

    // The backend accepts at most 10 history entries per request, so only
    // send the most recent ones (otherwise long chats fail with a 422).
    final allHistory = List<ConversationEntry>.from(_messages);
    final historyForRequest = _profile!.privacySettings.aiMemoryEnabled
        ? (allHistory.length > 10
              ? allHistory.sublist(allHistory.length - 10)
              : allHistory)
        : <ConversationEntry>[];

    final profileContext = _buildProfileContext();

    // If there's no typed text but there is an attachment, still show
    // something sensible in the chat bubble.
    final displayText = text.isNotEmpty ? text : '📎 ${attachment!.name}';

    final userEntry = ConversationEntry(
      timestamp: DateTime.now(),
      role: 'user',
      message: displayText,
      sessionId: _currentSessionId,
    );
    setState(() => _messages.add(userEntry));
    _scrollToBottom();

    await _profileService.appendConversationEntry(
      'user',
      displayText,
      sessionId: _currentSessionId,
    );

    try {
      final result = await _aiService.sendMessage(
        message: text,
        history: historyForRequest,
        profileContext: profileContext,
        language: _language,
        attachment: attachment == null
            ? null
            : ChatAttachment(
                fileName: attachment.name,
                mimeType: _mimeTypeFor(attachment.name),
                base64Data: base64Encode(attachment.bytes!),
              ),
      );

      final assistantEntry = ConversationEntry(
        timestamp: DateTime.now(),
        role: 'assistant',
        message: result.reply,
        sessionId: _currentSessionId,
      );

      await _profileService.appendConversationEntry(
        'assistant',
        result.reply,
        sessionId: _currentSessionId,
      );

      if (!mounted) return;
      // Commit the reply to the UI FIRST. Applying the AI's profile
      // updates happens afterwards in its own contained step, so a
      // malformed structured payload can never swallow the answer the
      // user is waiting for (task 1.7).
      setState(() {
        _messages.add(assistantEntry);
        _navHint =
            chatNavHintForTab(result.suggestedTab) ??
            detectChatNavHint(userText: text, replyText: result.reply);
        if (result.crisisConcern) _showCrisisBanner = true;
        if (result.medicalEmergencyConcern) _showMedicalEmergencyBanner = true;
        _sending = false;
      });
      _scrollToBottom();

      await _applyProfileUpdates(result.profileUpdates);
    } catch (e) {
      if (!mounted) return;
      // Restore exactly what the user was sending, so a failed send can
      // be retried (button below, or just pressing send) without
      // retyping (task 1.7).
      _inputController.text = text;
      setState(() {
        _sending = false;
        _needsSignIn = e is AuthRequiredException;
        _sendFailed = true;
        _pendingAttachment = attachment;
        _errorText = e is AuthRequiredException
            ? e.message
            : e is ChatServerException
            ? e.message
            : "Couldn't reach the check-in assistant. Please check "
                  'your internet connection and try again.';
      });
    }
  }

  /// Applies the AI's structured profile updates -- allow-listed and
  /// type-checked by chat_profile_updates.dart -- and offers an Undo
  /// snackbar afterwards. Any failure here is contained: the reply is
  /// already on screen and the user's own data is never at risk.
  Future<void> _applyProfileUpdates(Map<String, dynamic>? rawUpdates) async {
    if (rawUpdates == null || rawUpdates.isEmpty) return;
    final updates = sanitizeChatProfileUpdates(rawUpdates);
    if (updates == null) return;

    final previous = _profileService.profileUpdated.value ?? _profile;
    if (previous == null) return; // no snapshot to undo with
    try {
      final updated = await _profileService.updateProfile(
        (p) => applyChatProfileUpdates(p, updates),
      );
      if (!mounted) return;
      setState(() => _profile = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Saheli updated your health profile.'),
          action: SnackBarAction(
            label: _language == 'ur' ? 'منسوخ کریں' : 'Undo',
            onPressed: () => _undoProfileUpdates(previous),
          ),
        ),
      );
    } catch (e) {
      debugPrint('ai profile update failed: $e');
      // Reflect whatever state the service actually committed, if any.
      if (!mounted) return;
      final committed = _profileService.profileUpdated.value;
      if (committed != null) setState(() => _profile = committed);
    }
  }

  /// Undo: restores exactly the three sections the AI was allowed to
  /// touch, keeping any unrelated changes made in the meantime.
  Future<void> _undoProfileUpdates(HealthProfile previous) async {
    try {
      final restored = await _profileService.updateProfile(
        (p) => p.copyWith(
          lifestyle: previous.lifestyle,
          mentalHealth: previous.mentalHealth,
          reproductiveHistory: previous.reproductiveHistory,
        ),
      );
      if (!mounted) return;
      setState(() => _profile = restored);
    } catch (e) {
      debugPrint('profile update undo failed: $e');
    }
  }

  Map<String, dynamic> _buildProfileContext() {
    final p = _profile!;
    final cycle = context.read<CycleProvider>().cycleData;

    final ctx = <String, dynamic>{
      'demographics': {
        'age_yrs': p.demographics.ageYrs,
        'marital_status': p.demographics.maritalStatus,
      },
      'lifestyle': p.lifestyle.toJson(),
      'mental_health': p.mentalHealth.toJson(),
      'reproductive_history': {
        'cycle_regularity': p.reproductiveHistory.cycleRegularity,
        'current_contraception_method':
            p.reproductiveHistory.currentContraceptionMethod,
      },
      'pcos_history_count': p.pcosHistory.length,
      'latest_pcos_result': p.pcosHistory.isNotEmpty
          ? p.pcosHistory.last.prediction
          : null,
      'cycle': {
        'current_cycle_day': cycle.getCurrentCycleDay(),
        'phase': cycle.getPhase(),
        'days_until_next_period': cycle.daysUntilNextPeriod(),
      },
    };

    if (p.privacySettings.aiCanAccessDiary && p.diaryEntries.isNotEmpty) {
      final recent = p.diaryEntries.length > 5
          ? p.diaryEntries.sublist(p.diaryEntries.length - 5)
          : p.diaryEntries;
      ctx['recent_diary_entries'] = recent
          .map(
            (d) => {
              'date': d.date.toIso8601String(),
              'mood': d.mood,
              'symptom_tags': d.symptomTags,
              'text': d.text,
            },
          )
          .toList();
    }

    return ctx;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // One app-wide switch (the fixed EN | اردو pill) drives both this
    // screen's UI language and what language Saheli replies in.
    _language = context.watch<LanguageProvider>().code;

    return ColoredBox(
      color: _cBg,
      child: SafeArea(
        child: Column(
          children: [
            _topBar(),
            if (_showMedicalEmergencyBanner) _medicalEmergencyBanner(),
            if (_showCrisisBanner) _crisisBanner(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < _messages.length) {
                    return _messageBubble(_messages[index]);
                  }
                  return _typingBubble();
                },
              ),
            ),
            if (_navHint != null) _navHintBanner(_navHint!),
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _errorText!,
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.periodRed,
                  ),
                ),
              ),
            if (_needsSignIn)
              TextButton(
                onPressed: _goToSignIn,
                child: Text(
                  _language == 'ur' ? 'دوبارہ سائن اِن کریں' : 'Sign in again',
                  style: AppTextStyles.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: _cClay,
                  ),
                ),
              ),
            // Task 1.7: after a failed send the user's text and
            // attachment are back in the input -- this just re-sends
            // them as-is.
            if (_sendFailed && _errorText != null && !_needsSignIn)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _sending ? null : _sendMessage,
                    icon: Icon(Icons.refresh, size: 18, color: _cClay),
                    label: Text(
                      _language == 'ur' ? 'دوبارہ کوشش کریں' : 'Retry',
                      style: AppTextStyles.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: _cClay,
                      ),
                    ),
                  ),
                ),
              ),
            if (_messages.length <= 1) _starterChips(),
            if (_pendingAttachment != null) _attachmentChip(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  /// Claude-style starter prompts on a fresh chat -- one tap sends (and
  /// remembers) a common check-in opener. They vanish after the first
  /// exchange.
  static const _starters = [
    'How have I been feeling this week?',
    'A quick check-in on my sleep and stress',
    'I want to journal about today',
  ];

  Widget _starterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in _starters)
            GestureDetector(
              onTap: () {
                if (_sending) return;
                _inputController.text = s;
                _sendMessage();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _cWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '✦',
                      style: TextStyle(fontSize: 10, color: _cClay),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr(s),
                      style: AppTextStyles.sans(size: 12.5, color: _cText),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
      decoration: BoxDecoration(
        color: _cBg,
        border: Border(bottom: BorderSide(color: _cBorder)),
      ),
      child: Row(
        children: [
          // Claude-style star mark in a soft terracotta disc.
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: _cClaySoft,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('✦', style: TextStyle(fontSize: 14, color: _cClay)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Saheli'),
                  style: AppTextStyles.serif(
                    size: 19,
                    weight: FontWeight.w600,
                    color: _cText,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  tr('Your check-in companion'),
                  style: AppTextStyles.sans(size: 10.5, color: _cMuted),
                ),
              ],
            ),
          ),
          IconButton(
            // AI privacy controls, right where the AI operates: opens a
            // bottom sheet with the same toggles as Settings >
            // Data & Privacy (what Saheli may remember / read).
            tooltip: tr('AI privacy controls'),
            onPressed: _openPrivacySheet,
            icon: const Icon(Icons.shield_outlined),
            color: _cMuted,
            iconSize: 20,
          ),
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded),
            color: _cMuted,
            iconSize: 20,
          ),
          IconButton(
            onPressed: _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
            color: _cMuted,
            iconSize: 20,
          ),
          // Trailing clearance so the fixed global language pill (pinned
          // top-right on every screen) never covers these buttons.
          const SizedBox(width: 94),
        ],
      ),
    );
  }

  Widget _medicalEmergencyBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.periodRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.periodRed.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, size: 18, color: AppColors.periodRed),
              const SizedBox(width: 8),
              Text(
                'This may need urgent medical care',
                style: AppTextStyles.sans(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.periodRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'What you\'ve described could be a medical emergency. Please '
            'seek in-person medical attention now -- an emergency room or '
            'urgent care -- rather than continuing to rely on this chat.',
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _crisisBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.periodRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.periodRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, size: 16, color: AppColors.periodRed),
              const SizedBox(width: 8),
              Text(
                tr('You matter, and support is available'),
                style: AppTextStyles.sans(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.periodRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'If things feel like too much right now, please consider reaching '
            'out to a crisis helpline in your area, or to someone you trust.',
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Befrienders Worldwide (befrienders.org) lists crisis lines by country.',
            style: AppTextStyles.sans(
              size: 11,
              color: AppColors.periodRed,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ConversationEntry entry) {
    final isUser = entry.role == 'user';
    if (isUser) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cUserBubble,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cBorder),
          ),
          child: Text(
            entry.message,
            style: AppTextStyles.sans(size: 13.5, color: _cText),
          ),
        ),
      );
    }

    // Claude-style assistant turn: plain, unhurried text on the paper
    // background under a small star + name row -- no boxed bubble, so
    // longer replies read like a letter instead of a chat app.
    final hour = entry.timestamp.hour % 12 == 0
        ? 12
        : entry.timestamp.hour % 12;
    final stamp =
        '$hour:${entry.timestamp.minute.toString().padLeft(2, '0')} '
        '${entry.timestamp.hour >= 12 ? 'pm' : 'am'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _cClay,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    '✦',
                    style: TextStyle(fontSize: 10, color: Color(0x99FFFFFF)),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                tr('Saheli'),
                style: AppTextStyles.sans(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: _cClay,
                ),
              ),
              const SizedBox(width: 7),
              Text(stamp, style: AppTextStyles.sans(size: 10, color: _cMuted)),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            entry.message,
            style: AppTextStyles.sans(
              size: 14,
              color: _cText,
            ).copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }

  /// Clears the dead session and opens Sign In (no half-logged-in limbo).
  Future<void> _goToSignIn() async {
    final provider = context.read<CycleProvider>();
    final navigator = Navigator.of(context);
    await provider.clearSession();
    if (!mounted) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (route) => false,
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TypingDots(),
            const SizedBox(width: 9),
            Text(
              tr('Saheli is thinking…'),
              style: AppTextStyles.sans(size: 12, color: _cMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _openNavHint(ChatNavHint hint) {
    if (hint.target == 'diary') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const HealthDiaryScreen()));
    } else if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(hint.target);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open the ${hint.labelEn} tab to check this out'),
        ),
      );
    }
    setState(() => _navHint = null);
  }

  /// Pop-up pinned just above the input bar, e.g. "Take me to PCOS".
  Widget _navHintBanner(ChatNavHint hint) {
    final isUr = _language == 'ur';
    final color = hint.color;
    return Directionality(
      textDirection: isUr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: _cWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(hint.icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUr
                        ? '${hint.label(_language)} پر جائیں؟'
                        : 'Take me to ${hint.label(_language)}?',
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: _cText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint.reason(_language),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sans(size: 11.5, color: _cMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _openNavHint(hint),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cClay,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                isUr ? 'لے جائیں' : tr('Take me there'),
                style: AppTextStyles.sans(
                  size: 12,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              tooltip: isUr ? 'بند کریں' : tr('Dismiss'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: _cMuted),
              onPressed: () => setState(() => _navHint = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentChip() {
    final file = _pendingAttachment!;
    final isImage = _mimeTypeFor(file.name).startsWith('image/');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cClaySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cClay.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
            size: 16,
            color: _cClay,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.sans(size: 12.5, weight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: _removeAttachment,
            child: Icon(Icons.close, size: 16, color: _cMuted),
          ),
        ],
      ),
    );
  }

  /// Intercepts the hardware Enter key on desktop/web so it sends the
  /// message instead of inserting a newline. Shift+Enter still inserts
  /// a newline for multi-line messages.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    if (shiftHeld) return KeyEventResult.ignored; // allow newline

    _sendMessage();
    return KeyEventResult.handled;
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      color: _cBg,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: _cWhite,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _cBorder),
          boxShadow: [
            BoxShadow(
              // Claude's composer floats on a soft default shadow, no
              // hard outline only.
              color: _cClay.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _pickingFile ? null : _pickAttachment,
              icon: _pickingFile
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              color: _cMuted,
              iconSize: 20,
              tooltip: tr('Attach a photo or document'),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: _handleKey,
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textDirection: _language == 'ur'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  style: AppTextStyles.sans(size: 13.5, color: _cText),
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: _listening
                        ? tr('Listening…')
                        : (_language == 'ur'
                              ? 'سہیلی کو پیغام بھیجیں…'
                              : tr('Message Saheli…')),
                    hintStyle: AppTextStyles.sans(size: 13, color: _cMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _toggleListening,
              icon: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
              ),
              color: _listening ? _cClay : _cMuted,
              iconSize: 20,
              tooltip: _speechAvailable
                  ? (_listening ? tr('Stop recording') : tr('Voice message'))
                  : tr('Voice input not available in this browser'),
            ),
            _sending
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    color: Colors.white,
                    iconSize: 18,
                    style: IconButton.styleFrom(
                      backgroundColor: _cClay,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// Claude-style "thinking" indicator: three softly pulsing terracotta dots.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Stagger: dot i peaks slightly after the previous one.
            final t = (_controller.value - i * 0.22) % 1.0;
            final up = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: 0.8 + 0.35 * up,
                child: Opacity(
                  opacity: (0.35 + 0.6 * up).clamp(0.0, 1.0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _cClay,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Bottom sheet holding the two AI privacy toggles -- the same settings
/// stored in the profile's privacySettings (canonical edit home is
/// Settings > Data & Privacy). Surfaced in the AI chat header because
/// that's where their effect is instantly visible: with memory off, the
/// next message sends no history; with diary access off, journal text is
/// excluded from the assistant's context.
class _PrivacySheet extends StatefulWidget {
  const _PrivacySheet({
    required this.initialProfile,
    required this.service,
    required this.onProfileUpdated,
  });

  final HealthProfile initialProfile;
  final HealthProfileService service;
  final ValueChanged<HealthProfile> onProfileUpdated;

  @override
  State<_PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends State<_PrivacySheet> {
  late HealthProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
  }

  Future<void> _toggle({required String field, required bool value}) async {
    final updated = await widget.service.updateProfile(
      (p) => p.copyWith(
        privacySettings: p.privacySettings.copyWith(
          aiCanAccessDiary: field == 'diary' ? value : null,
          aiMemoryEnabled: field == 'memory' ? value : null,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _profile = updated);
    widget.onProfileUpdated(updated);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _profile.privacySettings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI privacy',
              style: AppTextStyles.sans(size: 16, weight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose what Saheli AI is allowed to do during check-ins.',
              style: AppTextStyles.sans(
                size: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📖', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI can read my diary',
                        style: AppTextStyles.sans(
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Off: Saheli won\'t reference your journal entries '
                        'in replies.',
                        style: AppTextStyles.sans(
                          size: 11,
                          color: AppColors.textSecondary,
                        ).copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.aiCanAccessDiary,
                  onChanged: (v) => _toggle(field: 'diary', value: v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🧠', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI remembers past conversations',
                        style: AppTextStyles.sans(
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Off: every message is sent with no chat history, '
                        'even within this session.',
                        style: AppTextStyles.sans(
                          size: 11,
                          color: AppColors.textSecondary,
                        ).copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: settings.aiMemoryEnabled,
                  onChanged: (v) => _toggle(field: 'memory', value: v),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'These same controls also live in Settings > Data & Privacy, '
              'along with "Clear AI memory" and "Delete diary entries".',
              style: AppTextStyles.sans(
                size: 11,
                color: AppColors.textSecondary,
              ).copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
