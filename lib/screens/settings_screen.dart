import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/cycle_provider.dart';
import '../services/auth_session.dart';
import '../theme/app_theme.dart';
import 'cycle_data_screen.dart';
import 'about_screen.dart';
import 'terms_screen.dart';
import 'data_privacy_screen.dart';
import 'sign_in_screen.dart';
import 'health_diary_screen.dart'; // ← NEW IMPORT
import 'profile_edit_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userName = 'Your Name';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    // Read through the same per-account scoping the provider writes:
    // the bare legacy key until an account claims it, then
    // `userName:<account id>` for whoever is signed in.
    await AuthSession.ensureLoaded();
    final userId = AuthSession.userId;
    final prefs = await SharedPreferences.getInstance();
    var savedName = (userId != null && userId.isNotEmpty)
        ? prefs.getString('userName:$userId')
        : null;
    savedName ??= prefs.getString('userName');
    if (savedName != null && savedName.isNotEmpty && mounted) {
      final name = savedName; // capture for the closure (no promotion)
      setState(() => _userName = name);
    }
  }

  Future<void> _saveUserName(String name) async {
    // Writes the scoped key (falls back to the bare key when signed
    // out) and notifies the whole app -- bypassing the provider here
    // would leave a second account reading the previous account's name.
    context.read<CycleProvider>().updateUserName(name);
  }

  @override
  Widget build(BuildContext context) {
    final cycle = context.watch<CycleProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: AppTextStyles.serif(size: 22)),
              const SizedBox(height: 20),
              _profileCard(),

              const SizedBox(height: 20),
              _sectionHeading('HEALTH'),
              const SizedBox(height: 10),
              _settingsRow(
                context,
                Icons.auto_stories_outlined,
                'My Health Diary',
                'View',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HealthDiaryScreen(),
                    ),
                  );
                },
              ),
              // SRS FR-84: direct profile editor (the Diary's Profile
              // tab links here too).
              _settingsRow(
                context,
                Icons.person_outline,
                'Health Profile',
                'Edit',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileEditScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              _sectionHeading('CYCLE'),
              const SizedBox(height: 10),
              _settingsRow(
                context,
                Icons.water_drop_outlined,
                'Cycle Data',
                'Edit',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CycleDataScreen(),
                    ),
                  );
                },
              ),
              _reminderToggleRow(context, cycle),

              const SizedBox(height: 20),
              // Task 2.5: Data & Privacy is an app-wide privacy surface,
              // not a cycle setting -- its own group now.
              _sectionHeading('PRIVACY & DATA'),
              const SizedBox(height: 10),
              _settingsRow(
                context,
                Icons.privacy_tip_outlined,
                'Data & Privacy',
                'Manage',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DataPrivacyScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              _sectionHeading('ABOUT'),
              const SizedBox(height: 10),
              _settingsRow(
                context,
                Icons.info_outline,
                'About Wellness Saheli',
                '',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                context,
                Icons.description_outlined,
                'Terms & Privacy',
                '',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TermsScreen(),
                    ),
                  );
                },
              ),
              _settingsRow(
                context,
                Icons.star_outline,
                'Rate the App',
                '',
                () => _showRateDialog(context),
              ),

              const SizedBox(height: 20),
              _logoutButton(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String text) {
    return Text(
      text,
      style: AppTextStyles.sans(
        size: 11,
        weight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _profileCard() {
    return GestureDetector(
      onTap: () => _showEditNameDialog(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.cardBorder,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: AppColors.textSecondary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName,
                    style: AppTextStyles.sans(
                      size: 15,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edit Profile',
                    style: AppTextStyles.sans(
                      size: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog(BuildContext context) {
    final controller = TextEditingController(
      text: _userName == 'Your Name' ? '' : _userName,
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Edit Name',
          style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.sans(size: 14),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: AppTextStyles.sans(
              size: 14,
              color: AppColors.textSecondary,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              final finalName = newName.isEmpty ? 'Your Name' : newName;
              setState(() => _userName = finalName);
              _saveUserName(finalName);
              Navigator.pop(dialogContext);
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
    VoidCallback? onTap,
  ) {
    // Task 2.5: real icon chips instead of emoji glyphs, plus button
    // semantics so screen readers announce these as actions. The chip
    // matches the reminders row (task 2.2) so the screen has one row
    // language.
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
                ),
              ),
              if (value.isNotEmpty) ...[
                Text(
                  value,
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Icon(
                Icons.chevron_right,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reminderToggleRow(BuildContext context, CycleProvider cycle) {
    // Task 2.2: a real settings row instead of an emoji + a bare switch.
    // The whole row is the tap target (not just the 48dp switch), the
    // switch renders through the app's single switchTheme, and the
    // subtitle is honest: the preference is persisted per account, but
    // nothing schedules notifications yet. (Whether the default should
    // stay ON is with the owner -- docs/OPEN_QUESTIONS.md.)
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.read<CycleProvider>().toggleReminders(
          !cycle.remindersEnabled,
        ),
        child: Semantics(
          toggled: cycle.remindersEnabled,
          label: 'Reminders',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.blush,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.notifications_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reminders',
                        style: AppTextStyles.sans(
                          size: 14,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Saved on this device. Notification delivery isn't "
                        'set up yet.',
                        style: AppTextStyles.sans(
                          size: 11,
                          color: AppColors.textSecondary,
                        ).copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: cycle.remindersEnabled,
                  onChanged: (val) {
                    context.read<CycleProvider>().toggleReminders(val);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLogoutDialog(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          'Log Out',
          style: AppTextStyles.sans(
            size: 14,
            weight: FontWeight.w600,
            color: const Color(0xFFE57373),
          ),
        ),
      ),
    );
  }

  /// Three honest outcomes (task 1.1): the old dialog pretended "log
  /// out" meant one thing while silently keeping data; now the user
  /// explicitly chooses between keeping data on the device and erasing
  /// it before leaving.
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Log Out',
          style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          'Sign out and keep your cycle data on this device, or erase it '
          'from the device too? Your account and anything already synced '
          'to the server are not deleted.',
          style: AppTextStyles.sans(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                _finishLogout(context, dialogContext, removeData: false),
            child: Text(
              'Keep data on device',
              style: AppTextStyles.sans(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                _finishLogout(context, dialogContext, removeData: true),
            child: Text(
              'Remove cycle data & log out',
              style: AppTextStyles.sans(
                size: 13,
                weight: FontWeight.w600,
                color: const Color(0xFFE57373),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Closes the dialog, performs the actual logout (awaited, so the
  /// local wipe finishes before navigation) and returns the user to
  /// Sign In with the whole stack cleared behind it.
  Future<void> _finishLogout(
    BuildContext context,
    BuildContext dialogContext, {
    required bool removeData,
  }) async {
    // Capture everything needed across the await BEFORE it, so no
    // widget/deactivated-context access happens after the dialog closes.
    final provider = context.read<CycleProvider>();
    final navigator = Navigator.of(context);
    Navigator.pop(dialogContext); // close the confirmation dialog first

    // The server token invalidation inside logout() is best-effort, but
    // the local session/data wipe completes before we navigate on.
    await provider.logout(removeData: removeData);

    if (context.mounted) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
        (route) => false,
      );
    }
  }

  void _showRateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Rate the App',
          style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          'Thanks for using Wellness Saheli! App store rating will be available once the app is published.',
          style: AppTextStyles.sans(size: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
