import 'package:flutter/material.dart' hide Text;
import 'package:provider/provider.dart';
import '../l10n/app_text.dart';
import '../theme/app_theme.dart';
import '../config/disclosures.dart';
import '../models/health_profile.dart';
import '../providers/cycle_provider.dart';
import '../services/auth_session.dart';
import '../services/health_profile_service.dart';
import 'sign_in_screen.dart';

class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  final HealthProfileService _service = HealthProfileService();
  HealthProfile? _profile;
  bool _loading = true;

  /// Whether a usable session exists. Only a signed-in account has data
  /// on the server (anonymous, device-only usage never uploads), so the
  /// server-deletion section is shown only in that case.
  bool _signedIn = false;

  /// True while the server deletion request is in flight.
  bool _deletingServerData = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AuthSession.ensureLoaded();
    final signedIn = AuthSession.isValid;
    final profile = await _service.loadProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
      _signedIn = signedIn;
    });
  }

  Future<void> _setAiCanAccessDiary(bool value) async {
    final updated = await _service.updateProfile(
      (p) => p.copyWith(
        privacySettings: p.privacySettings.copyWith(aiCanAccessDiary: value),
      ),
    );
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _setAiMemoryEnabled(bool value) async {
    final updated = await _service.updateProfile(
      (p) => p.copyWith(
        privacySettings: p.privacySettings.copyWith(aiMemoryEnabled: value),
      ),
    );
    if (!mounted) return;
    setState(() => _profile = updated);
  }

  Future<void> _confirmAndClearAiMemory() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear AI conversation memory?',
      body:
          'This deletes every past check-in conversation Saheli AI has '
          'recorded. It does not affect your diary entries, PCOS checks, '
          'or contraception history. This can\'t be undone.',
      confirmLabel: 'Clear memory',
    );
    if (confirmed != true) return;

    final updated = await _service.updateProfile(
      (p) => p.copyWith(conversationLog: const []),
    );
    if (!mounted) return;
    setState(() => _profile = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI conversation memory cleared')),
    );
  }

  Future<void> _confirmAndDeleteDiaryEntries() async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete all diary entries?',
      body:
          'This permanently deletes everything you\'ve written in your '
          'diary. It does not affect your cycle logs, PCOS checks, or AI '
          'conversation history. This can\'t be undone.',
      confirmLabel: 'Delete entries',
    );
    if (confirmed != true) return;

    final updated = await _service.updateProfile(
      (p) => p.copyWith(diaryEntries: const []),
    );
    if (!mounted) return;
    setState(() => _profile = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All diary entries deleted')));
  }

  /// Deletes the account's server-side profile copy, then clears the
  /// on-device data and signs the user out.
  ///
  /// The local wipe is part of the success path on purpose: with the
  /// server copy gone, any remaining local data would be re-uploaded by
  /// the next background sync. Failure keeps everything (server and
  /// local) exactly as it was and just reports why.
  Future<void> _deleteServerData() async {
    // Capture everything needed across the awaits BEFORE the first one,
    // so no deactivated-widget access happens after the dialog closes
    // (same pattern as the Settings logout flow).
    final provider = context.read<CycleProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await _showConfirmDialog(
      title: 'Delete my data from the server?',
      body:
          'This permanently deletes the server copy of your health '
          'profile — including your diary entries, AI conversation '
          'history, PCOS and eligibility check results, and the profile '
          'details you\'ve entered. The app\'s local data is removed too, '
          'and you\'ll be signed out. Your account itself stays '
          'registered. This can\'t be undone.',
      confirmLabel: 'Delete my data',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingServerData = true);
    try {
      final error = await _service.deleteServerProfile();
      if (!mounted) return;
      if (error != null) {
        setState(() => _deletingServerData = false);
        messenger.showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      // Server copy is gone: clear the on-device data and session too,
      // so nothing local can be synced back up afterwards.
      await provider.logout(removeData: true);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Your data has been deleted from the server and this device',
          ),
        ),
      );
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _deletingServerData = false);
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          title,
          style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          body,
          style: AppTextStyles.sans(
            size: 13,
            color: AppColors.textSecondary,
          ).copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _backHeader(context, 'Data & Privacy'),
              const SizedBox(height: 20),
              if (!_loading) ...[
                _aiPrivacySection(),
                const SizedBox(height: 24),
              ],
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.ovulationTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.ovulationTeal.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('🔒', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your daily period, symptom, and mood logs stay on '
                        'this device. Some other data — like your profile '
                        'and AI conversations — syncs to the Wellness '
                        'Saheli server when you\'re signed in, and check-in '
                        'messages are processed by $kAiProviderName. '
                        'Exactly what goes where is described below.',
                        style: AppTextStyles.sans(
                          size: 12,
                          color: AppColors.textPrimary,
                        ).copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _section(
                'What Stays on This Device',
                'Your daily logs — period dates, symptoms, moods, and '
                    'reminder preferences — are saved only in the app\'s own '
                    'storage on your phone, the same way notes or offline '
                    'apps keep data on your device. They are not uploaded '
                    'anywhere.',
              ),
              _section(
                'What Syncs to the Server',
                'When you\'re signed in, the app keeps a private copy of '
                    'your health profile on the Wellness Saheli server so '
                    'your data follows you across devices. That copy '
                    'includes: the profile details you enter (name, age, '
                    'demographics), lifestyle and contraception history, '
                    'cycle settings, your PCOS check results, your '
                    'eligibility check results, mental-health check answers, '
                    'your diary entries, and your AI conversation history. '
                    'The PCOS screening check and the contraceptive '
                    'eligibility checker also send the specific values you '
                    'enter on those screens to calculate a result — and that '
                    'result is saved in your profile history.',
              ),
              _section(
                'AI Check-Ins',
                'When you message Saheli AI, your message is sent to the '
                    'Wellness Saheli server and processed by $kAiProviderName. '
                    'If "AI remembers past conversations" is on, earlier '
                    'check-in messages are included as context; if "AI can '
                    'read my diary" is on, your recent diary entries are '
                    'included too. Everything you exchange stays in your AI '
                    'conversation history — part of the synced profile '
                    'described above — until you delete it with "Clear AI '
                    'memory", the per-message delete in the AI check-in, or '
                    '"Delete my data from the server".',
              ),
              _section(
                'Account & Login',
                'Creating an account stores your name, email, and login '
                    'credentials on the Wellness Saheli server, so you can '
                    'sign in again later. Signing up requires verifying your '
                    'email with a 6-digit code. Your sign-in session itself '
                    'is kept on this device, and signing out invalidates it.',
              ),
              _section(
                'What We Don\'t Do',
                // OWNER: these are business-policy promises an owner must
                // stand behind; the code review can only verify that the
                // app and backend make no analytics/ad calls.
                'We don\'t run advertising or third-party analytics in '
                    'the app, and we don\'t sell or share your health data '
                    'with advertisers.',
              ),
              _section(
                'Why We Ask for This Data',
                'Cycle dates, symptoms, and moods you log power the '
                    'predictions and insights inside the app — your current '
                    'cycle day, upcoming period estimate, and fertility '
                    'window — and those are computed on this device. What '
                    'else can read that data is described above (the AI '
                    'check-in, only when you turn its toggles on).',
              ),
              _section(
                'Your Control',
                'You can edit or delete your cycle data any time from '
                    'Settings → Cycle Data, and delete individual entries '
                    'from the Health Diary timeline. Here you can clear the '
                    'AI memory and delete diary entries. If you\'re signed '
                    'in, "Delete my data from the server" below erases the '
                    'server copy of your profile and clears this device\'s '
                    'data too. Uninstalling the app removes what\'s stored '
                    'on this device.',
              ),
              _section(
                'If You Share Your Device',
                'Because data is stored locally, anyone with access to your unlocked phone could open the app and see your logs. If that\'s a concern, consider using your phone\'s built-in app lock or biometric lock features for extra privacy.',
              ),
              if (_signedIn) ...[
                const SizedBox(height: 24),
                _serverDataSection(),
              ],
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Privacy summary last updated $kPolicyLastUpdated',
                  style: AppTextStyles.sans(
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backHeader(BuildContext context, String title) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: AppTextStyles.serif(size: 20)),
      ],
    );
  }

  /// Danger zone: erase the account's server-side profile copy. Only
  /// shown when a session exists -- anonymous, device-only usage never
  /// uploads anything, so there'd be nothing on the server to delete.
  Widget _serverDataSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Data on the Server',
            style: AppTextStyles.sans(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Your account syncs a private copy of your health profile to '
            'the Wellness Saheli server — what that includes is described '
            'above. You can erase that server copy at any time. Deleting '
            'it also removes this app\'s locally stored data and signs '
            'you out. Your account itself stays registered.',
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _deletingServerData ? null : _deleteServerData,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _deletingServerData
                    ? AppColors.danger.withValues(alpha: 0.5)
                    : AppColors.danger,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: _deletingServerData
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Delete my data from the server',
                        style: AppTextStyles.sans(
                          size: 13,
                          weight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- AI & Diary privacy controls ----------------

  Widget _aiPrivacySection() {
    final settings = _profile!.privacySettings;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI & Diary Privacy',
            style: AppTextStyles.sans(size: 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Control what Saheli AI is allowed to remember and read about '
            'you. Check-in messages are sent to the Wellness Saheli '
            'server and processed by $kAiProviderName.',
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 16),
          _privacyToggleRow(
            emoji: '📖',
            title: 'AI can read my diary',
            subtitle:
                'When on, Saheli AI may reference your diary entries during '
                'check-ins to give more relevant guidance.',
            value: settings.aiCanAccessDiary,
            onChanged: _setAiCanAccessDiary,
          ),
          const SizedBox(height: 12),
          _privacyToggleRow(
            emoji: '🧠',
            title: 'AI remembers past conversations',
            subtitle:
                'When off, every check-in starts fresh with no memory of '
                'earlier conversations.',
            value: settings.aiMemoryEnabled,
            onChanged: _setAiMemoryEnabled,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _confirmAndClearAiMemory,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.cardBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Clear AI memory',
                    style: AppTextStyles.sans(
                      size: 12,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _confirmAndDeleteDiaryEntries,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Delete diary entries',
                    style: AppTextStyles.sans(
                      size: 12,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _privacyToggleRow({
    required String emoji,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.sans(size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.sans(
                  size: 11,
                  color: AppColors.textSecondary,
                ).copyWith(height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _section(String heading, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: AppTextStyles.sans(
              size: 14,
              weight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.sans(
              size: 13,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
