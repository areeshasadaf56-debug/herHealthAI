import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/cycle_provider.dart';
import '../models/health_profile.dart';
import '../services/health_profile_service.dart';
import '../widgets/month_calendar.dart';
import '../widgets/ai_welcome_card.dart';
import '../widgets/ai_suggestion_card.dart';
import 'cycle_data_screen.dart';
import 'health_diary_screen.dart';
import 'learn_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Called with a tab name ('checkin', 'pcos', 'protection', etc.) when
  /// something on this screen should switch the shell's selected bottom
  /// -nav tab. Wired from HomeShell:
  ///   HomeScreen(onNavigateToTab: (tab) => _navigateToTab(tab))
  final void Function(String tabName)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HealthProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    // Live profile updates: a diary entry saved from another screen, a
    // privacy toggle, or a background cross-device sync refreshes the
    // Home snapshot immediately instead of only on the next remount.
    HealthProfileService().profileUpdated.addListener(_onExternalProfileUpdate);
  }

  void _onExternalProfileUpdate() {
    if (!mounted) return;
    final updated = HealthProfileService().profileUpdated.value;
    if (updated == null) return;
    if (_profile != null && updated.userId != _profile!.userId) {
      return; // another account's document; not for this screen
    }
    setState(() => _profile = updated);
  }

  @override
  void dispose() {
    HealthProfileService().profileUpdated.removeListener(
      _onExternalProfileUpdate,
    );
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await HealthProfileService().loadProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  String _formattedDate() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  /// Navigate to AI Check-in via the shell's tab navigation
  void _openAiCheckin() {
    widget.onNavigateToTab?.call('checkin');
  }

  @override
  Widget build(BuildContext context) {
    final cycle = context.watch<CycleProvider>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and utility icons
            _buildHeader(context),
            const SizedBox(height: 20),

            // ===== PRIMARY FEATURE: AI Welcome Card =====
            AiWelcomeCard(
              userName: cycle.userName,
              onTap: _openAiCheckin,
              currentPhase: cycle.currentPhase,
              currentCycleDay: cycle.currentCycleDay,
              lastCheckIn: _profile?.mentalHealth.lastCheckIn,
              selfReportedStressLevel:
                  _profile?.mentalHealth.selfReportedStressLevel,
              latestDiaryMood:
                  _profile != null && _profile!.diaryEntries.isNotEmpty
                  ? _profile!.diaryEntries.last.mood
                  : null,
            ),
            const SizedBox(height: 24),

            // ===== CONTEXTUAL SUGGESTIONS =====
            _buildContextualSuggestions(cycle),
            const SizedBox(height: 28),

            // Cycle dial - moved down (secondary feature now)
            _buildCycleDial(cycle),
            const SizedBox(height: 24),

            // Status cards
            _buildStatusCards(cycle),
            const SizedBox(height: 24),

            // Today's mood + recent symptoms
            _buildTodaySnapshot(cycle),
            const SizedBox(height: 24),

            // Symptom/mood trends from the last 30 days
            _buildTrendsCard(cycle),
            const SizedBox(height: 24),

            // Calendar
            _sectionLabel('THIS WEEK'),
            const SizedBox(height: 10),
            const MonthCalendar(),
            const SizedBox(height: 24),

            // Quick logging
            _sectionLabel('LOG TODAY'),
            const SizedBox(height: 10),
            _buildLogButtons(context),
            const SizedBox(height: 24),

            // Insight
            _sectionLabel("TODAY'S INSIGHT"),
            const SizedBox(height: 10),
            _buildInsightCard(cycle),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Wellness ',
                style: AppTextStyles.serif(
                  size: 22,
                  weight: FontWeight.w600,
                  color: AppColors.accent,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
              TextSpan(
                text: 'Saheli',
                style: AppTextStyles.serif(
                  size: 22,
                  weight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Text(
              _formattedDate(),
              style: AppTextStyles.sans(
                size: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HealthDiaryScreen()),
                );
              },
              child: Icon(
                Icons.menu_book_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Contextual suggestions based on cycle phase or user data
  /// For now: show relevant suggestion cards
  Widget _buildContextualSuggestions(CycleProvider cycle) {
    // Example: Show different suggestions based on cycle phase
    final phase = cycle.currentPhase;
    String suggestionTitle = '';
    String suggestionDesc = '';
    IconData suggestionIcon = Icons.lightbulb_outline;
    Color suggestionColor = AppColors.primary;

    if (phase == 'Menstrual') {
      suggestionTitle = 'Self-Care During Period';
      suggestionDesc = 'Tips for managing discomfort and boosting energy';
      suggestionIcon = Icons.favorite_border;
      suggestionColor = AppColors.periodRed;
    } else if (phase == 'Ovulation') {
      suggestionTitle = 'Fertility Window Guide';
      suggestionDesc = 'Understanding ovulation and your most fertile days';
      suggestionIcon = Icons.wb_sunny;
      suggestionColor = AppColors.accent;
    } else if (phase == 'Luteal') {
      suggestionTitle = 'Managing Luteal Phase';
      suggestionDesc = 'Nutrition and exercise for this phase';
      suggestionIcon = Icons.nightlife_outlined;
      suggestionColor = AppColors.primary;
    } else {
      suggestionTitle = 'Explore Your Cycle';
      suggestionDesc = 'Learn more about your follicular phase';
      suggestionIcon = Icons.local_florist_outlined;
      suggestionColor = AppColors.primary;
    }

    return AiSuggestionCard(
      title: suggestionTitle,
      description: suggestionDesc,
      actionText: 'Learn More',
      icon: suggestionIcon,
      accentColor: suggestionColor,
      prominent: false,
      onTap: () {
        // Open the matching guide in the Learn tab
        LearnScreen.openTopic(suggestionTitle);
        widget.onNavigateToTab?.call('learn');
      },
    );
  }

  Widget _buildTodaySnapshot(CycleProvider cycle) {
    final today = cycle.getLogFor(DateTime.now());
    final hasMood = today.mood != null;
    final hasSymptoms = today.symptoms.isNotEmpty;

    if (!hasMood && !hasSymptoms) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          if (hasMood) ...[
            Text(
              today.mood!.split(' ').first,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Text(
              today.mood!.split(' ').skip(1).join(' '),
              style: AppTextStyles.sans(size: 12, weight: FontWeight.w600),
            ),
          ],
          if (hasMood && hasSymptoms) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 16, color: AppColors.cardBorder),
            const SizedBox(width: 12),
          ],
          if (hasSymptoms)
            Expanded(
              child: Text(
                today.symptoms.join(', '),
                style: AppTextStyles.sans(
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendsCard(CycleProvider cycle) {
    final now = DateTime.now();
    final logs = cycle.dailyLogs;

    final symptomCounts = <String, int>{};
    final moodCounts = <String, int>{};
    int loggedDays = 0;

    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final log = logs[key];
      if (log == null) continue;
      if (log.symptoms.isNotEmpty || log.mood != null) loggedDays++;
      for (final s in log.symptoms) {
        symptomCounts[s] = (symptomCounts[s] ?? 0) + 1;
      }
      if (log.mood != null) {
        moodCounts[log.mood!] = (moodCounts[log.mood!] ?? 0) + 1;
      }
    }

    if (loggedDays < 3) return const SizedBox.shrink();

    final topSymptoms = symptomCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topMood = moodCounts.entries.isEmpty
        ? null
        : (moodCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;

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
            'LAST 30 DAYS',
            style: AppTextStyles.sans(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (topMood != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'You most often felt ${topMood.key.split(' ').skip(1).join(' ').toLowerCase()} '
                '(${topMood.value} of $loggedDays logged days).',
                style: AppTextStyles.sans(
                  size: 12.5,
                  color: AppColors.textPrimary,
                ).copyWith(height: 1.4),
              ),
            ),
          if (topSymptoms.isNotEmpty)
            Text(
              'Most reported: ${topSymptoms.take(3).map((e) => '${e.key} (${e.value}x)').join(', ')}.',
              style: AppTextStyles.sans(
                size: 12.5,
                color: AppColors.textPrimary,
              ).copyWith(height: 1.4),
            ),
          const SizedBox(height: 8),
          Text(
            'This is an observation based on your logs, not a diagnosis. If a '
            'pattern is affecting your daily life, consider mentioning it to a '
            'healthcare professional.',
            style: AppTextStyles.sans(
              size: 11,
              color: AppColors.textSecondary,
            ).copyWith(fontStyle: FontStyle.italic, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.sans(
        size: 11,
        weight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildCycleDial(CycleProvider cycle) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cardBorder, width: 3),
              ),
            ),
            Positioned(
              top: -3,
              child: Container(
                width: 28,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Task 3.2: no period date recorded yet -> no
                // invented day number; the chip below becomes the way
                // to set it.
                Text(
                  cycle.hasPeriodData ? '${cycle.currentCycleDay}' : '–',
                  style: AppTextStyles.serif(
                    size: 42,
                    color: AppColors.periodRed,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CYCLE DAY',
                  style: AppTextStyles.sans(
                    size: 11,
                    weight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  // Task 3.2: unset state prompts for the date; once
                  // set, the chip shows lateness (task 3.3) or phase.
                  onTap: cycle.hasPeriodData
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CycleDataScreen(),
                            ),
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.periodRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cycle.isLate
                          ? '${cycle.daysLate} days late'
                          : cycle.hasPeriodData
                          ? cycle.currentPhase!
                          : 'Set period date',
                      style: AppTextStyles.sans(
                        size: 11,
                        color: AppColors.periodRed,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCards(CycleProvider cycle) {
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

    // Calendar-day arithmetic (task 3.4): raw Duration addition can
    // drift across a DST transition.
    final now = DateTime.now();
    String dateLabel(int daysAhead) {
      final d = DateTime(now.year, now.month, now.day + daysAhead);
      return '${months[d.month - 1]} ${d.day}';
    }

    // Task 3.3: the wrapped countdown lies once the period is due or
    // overdue (it restarts at "28d" on the due day), so those states
    // get their own honest display. Task 3.2: with no period date at
    // all, the cards say so instead of showing wrapped garbage.
    final String nextPeriodValue;
    final String nextPeriodSub;
    final String fertilityValue;
    final String fertilitySub;
    if (!cycle.hasPeriodData) {
      nextPeriodValue = '–';
      nextPeriodSub = 'Not set yet';
      fertilityValue = '–';
      fertilitySub = 'Set your period date';
    } else {
      final since = cycle.daysSinceLastPeriodStart;
      final lateDays = cycle.daysLate;
      if (lateDays > 0) {
        nextPeriodValue = 'Late';
        nextPeriodSub = '$lateDays days late';
      } else if (since != null && since >= cycle.cycleLength) {
        nextPeriodValue = 'Today';
        nextPeriodSub = dateLabel(0);
      } else {
        nextPeriodValue = '${cycle.daysUntilNextPeriod}d';
        nextPeriodSub = dateLabel(cycle.daysUntilNextPeriod ?? 0);
      }

      final isOvulation = cycle.currentPhase == 'Ovulation';
      final ovu = cycle.daysUntilOvulation;
      fertilityValue = isOvulation ? 'High' : 'Low';
      fertilitySub = isOvulation
          ? 'Fertile window'
          : ovu == null
          ? 'Set your period date'
          : 'Ovulation in ${ovu}d';
    }

    return Row(
      children: [
        Expanded(
          child: _statusCard(
            label: 'NEXT PERIOD',
            value: nextPeriodValue,
            subLabel: nextPeriodSub,
            accentColor: AppColors.periodRed,
            useAccent: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statusCard(
            label: 'FERTILITY',
            value: fertilityValue,
            subLabel: fertilitySub,
            accentColor: AppColors.textPrimary,
            useAccent: false,
          ),
        ),
      ],
    );
  }

  Widget _statusCard({
    required String label,
    required String value,
    required String subLabel,
    required Color accentColor,
    required bool useAccent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: useAccent
              ? accentColor.withValues(alpha: 0.35)
              : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.sans(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.serif(
              size: 22,
              color: useAccent ? accentColor : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subLabel,
            style: AppTextStyles.sans(size: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLogButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _logButton(
            context,
            Icons.water_drop,
            'Period Flow',
            AppColors.periodRed,
            () => _showFlowInfoDialog(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _logButton(
            context,
            Icons.nightlight_round,
            'Mood',
            AppColors.moodYellow,
            () => _showMoodPicker(context, DateTime.now()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _logButton(
            context,
            Icons.assignment_outlined,
            'Symptoms',
            AppColors.symptomOrange,
            () => _showSymptomPicker(context, DateTime.now()),
          ),
        ),
      ],
    );
  }

  Widget _logButton(
    BuildContext context,
    IconData icon,
    String label,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Center(child: Icon(icon, size: 18, color: iconColor)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.sans(
                size: 11,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showFlowInfoDialog(BuildContext context) {
    final options = [
      {'label': 'None', 'desc': 'No flow today'},
      {'label': 'Spotting', 'desc': 'Very light, occasional drops'},
      {'label': 'Light', 'desc': 'Light flow, pad/tampon change every 4-6 hrs'},
      {'label': 'Medium', 'desc': 'Regular flow, change every 3-4 hrs'},
      {'label': 'Heavy', 'desc': 'Heavy flow, change every 1-2 hrs'},
    ];

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
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Flow",
                    style: AppTextStyles.sans(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'How heavy is your flow today?',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((opt) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          context.read<CycleProvider>().logFlowIntensity(
                            DateTime.now(),
                            opt['label']!,
                          );
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Flow logged: ${opt['label']}'),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt['label']!,
                                style: AppTextStyles.sans(
                                  size: 14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt['desc']!,
                                style: AppTextStyles.sans(
                                  size: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMoodPicker(BuildContext context, DateTime date) {
    final moods = [
      '😊 Happy',
      '😐 Neutral',
      '😢 Sad',
      '😠 Irritable',
      '😴 Tired',
      '😰 Anxious',
    ];
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
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How are you feeling?',
                    style: AppTextStyles.sans(
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: moods.map((m) {
                      return GestureDetector(
                        onTap: () {
                          context.read<CycleProvider>().logMood(date, m);
                          Navigator.pop(sheetContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Mood logged: $m')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Text(m, style: AppTextStyles.sans(size: 13)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSymptomPicker(BuildContext context, DateTime date) {
    final allSymptoms = [
      'Cramps',
      'Headache',
      'Bloating',
      'Fatigue',
      'Nausea',
      'Back Pain',
      'Breast Tenderness',
      'Acne',
    ];
    final existing = context.read<CycleProvider>().getLogFor(date).symptoms;
    final selected = List<String>.from(existing);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Log Symptoms',
                        style: AppTextStyles.sans(
                          size: 16,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allSymptoms.map((s) {
                          final isSelected = selected.contains(s);
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  selected.remove(s);
                                } else {
                                  selected.add(s);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.cardBorder,
                                ),
                              ),
                              child: Text(
                                s,
                                style: AppTextStyles.sans(
                                  size: 13,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          onPressed: () {
                            context.read<CycleProvider>().logSymptoms(
                              date,
                              selected,
                            );
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Symptoms saved')),
                            );
                          },
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Map<String, dynamic> _phaseIconData(String phase) {
    switch (phase) {
      case 'Menstrual':
        return {'icon': Icons.water_drop, 'color': AppColors.periodRed};
      case 'Follicular':
        return {'icon': Icons.local_florist, 'color': AppColors.primary};
      case 'Ovulation':
        return {'icon': Icons.wb_sunny, 'color': AppColors.accent};
      case 'Luteal':
        return {'icon': Icons.nightlight_round, 'color': AppColors.primary};
      default:
        return {'icon': Icons.info_outline, 'color': AppColors.textSecondary};
    }
  }

  Widget _buildInsightCard(CycleProvider cycle) {
    final phase = cycle.currentPhase;
    // Task 3.2: with no period date there is no phase to describe --
    // a quiet hint instead of a fabricated "null Phase" card.
    if (phase == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No cycle data yet',
                    style: AppTextStyles.sans(
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Set your last period start date in Settings to see '
                    'phase insights here.',
                    style: AppTextStyles.sans(
                      size: 12,
                      color: AppColors.textSecondary,
                    ).copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final phaseInfo = _phaseDetails(phase);
    final iconData = _phaseIconData(phase);
    final IconData phaseIcon = iconData['icon'] as IconData;
    final Color phaseColor = iconData['color'] as Color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: phaseColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Icon(phaseIcon, size: 18, color: phaseColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$phase Phase',
                  style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  phaseInfo,
                  style: AppTextStyles.sans(
                    size: 12,
                    color: AppColors.textSecondary,
                  ).copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _phaseDetails(String phase) {
    switch (phase) {
      case 'Menstrual':
        return 'Your uterine lining is shedding, which is why energy tends to run low right now. Rest when you can and don\'t feel guilty about slowing down. Iron-rich foods like spinach, lentils[...]';
      case 'Follicular':
        return 'Estrogen is climbing steadily, and most people feel their energy, mood, and focus lifting day by day. This is usually the best window for starting new projects, tackling harder wo[...]';
      case 'Ovulation':
        return 'This is your most fertile window, typically lasting about 24 hours around the release of an egg, though sperm can survive several days beforehand. Estrogen peaks and testosterone [...]';
      case 'Luteal':
        return 'Progesterone rises after ovulation and then drops sharply if pregnancy doesn\'t occur, which is what drives PMS symptoms like irritability, bloating, breast tenderness, and food c[...]';
      default:
        return 'Track your cycle regularly to get personalized insights about each phase.';
    }
  }
}
