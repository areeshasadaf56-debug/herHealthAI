import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/health_profile.dart';
import '../services/health_profile_service.dart';
import '../providers/cycle_provider.dart';
import '../widgets/app_animations.dart';
import '../widgets/diary_entry_dialog.dart';
import '../widgets/profile_sync_badge.dart';

/// Unified entry type so PCOS results, contraception changes, AI
/// conversation turns, written journal entries, and cycle logs (period
/// flow, mood, symptoms) can all live in one sorted timeline.
enum _EntryKind { pcos, contraception, conversation, cycle, eligibility, diary }

class _TimelineEntry {
  final DateTime date;
  final _EntryKind kind;
  final String title;
  final String subtitle;
  final Color color;
  final String emoji;

  /// What this tile maps back to, so the delete button can remove exactly
  /// this entry (per-kind fields, see _confirmDeleteEntry):
  ///   pcos            -> index into profile.pcosHistory
  ///   contraception   -> index into reproductiveHistory.contraceptionHistory
  ///   eligibility     -> index into profile.eligibilityHistory
  ///   conversation    -> index into profile.conversationLog
  ///   diary           -> index into profile.diaryEntries
  ///   cycle           -> "_dailyLogs" date key + which field of that day
  final int? listIndex;
  final String? dateKey;
  final String? cycleField; // 'period' | 'mood' | 'symptoms'

  const _TimelineEntry({
    required this.date,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.emoji,
    this.listIndex,
    this.dateKey,
    this.cycleField,
  });
}

class HealthDiaryScreen extends StatefulWidget {
  const HealthDiaryScreen({super.key});

  @override
  State<HealthDiaryScreen> createState() => _HealthDiaryScreenState();
}

class _HealthDiaryScreenState extends State<HealthDiaryScreen> {
  static const _shortMonths = [
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
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final _service = HealthProfileService();
  HealthProfile? _profile;
  bool _loading = true;
  bool _refreshing = false;
  int _activeTab = 0; // 0 = Timeline, 1 = Profile Summary

  @override
  void initState() {
    super.initState();
    _load();
    // A background sync can adopt a newer copy from the account at any
    // moment (that's exactly what the old refresh button silently did
    // and never showed). Listen and re-render when it does.
    _service.profileUpdated.addListener(_onProfileSynced);
  }

  void _onProfileSynced() {
    final updated = _service.profileUpdated.value;
    if (updated == null || !mounted) return;
    if (_profile == null ||
        updated.lastUpdated.isAfter(_profile!.lastUpdated)) {
      setState(() => _profile = updated);
    }
  }

  @override
  void dispose() {
    _service.profileUpdated.removeListener(_onProfileSynced);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await _service.loadProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  /// The refresh button / pull-to-refresh: explicitly awaits the server
  /// (instead of the old read-local-cache-instantly behavior that made
  /// it look dead), then says honestly what happened.
  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final before = _service.profileUpdated.value;
    try {
      final profile = await _service.loadProfile(forceServer: true);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _refreshing = false;
      });

      final after = _service.profileUpdated.value;
      final adopted = after != null && !identical(before, after);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adopted
                ? tr('Diary updated from your account')
                : _service.lastServerSyncReached
                ? tr("You're all caught up")
                : tr(
                    "Couldn't reach the server -- showing what's "
                    'saved on this device',
                  ),
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Parses the "yyyy-MM-dd" keys CycleProvider uses for _dailyLogs back
  /// into a DateTime, so cycle log entries can be sorted alongside
  /// PCOS/contraception/conversation entries on the same timeline.
  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  List<_TimelineEntry> _buildTimeline(
    HealthProfile p,
    Map<String, dynamic> dailyLogs,
  ) {
    final entries = <_TimelineEntry>[];

    for (var i = 0; i < p.pcosHistory.length; i++) {
      final r = p.pcosHistory[i];
      final positive =
          r.prediction.toLowerCase().contains('detected') &&
          !r.prediction.toLowerCase().contains('no pcos');
      entries.add(
        _TimelineEntry(
          date: r.date,
          kind: _EntryKind.pcos,
          title: 'PCOS Check — ${r.prediction}',
          subtitle:
              'Likelihood: ${(r.pcosProbability * 100).clamp(0, 100).toStringAsFixed(1)}% · ${r.modelUsed}',
          color: positive ? AppColors.periodRed : AppColors.ovulationTeal,
          emoji: '🧪',
          listIndex: i,
        ),
      );
    }

    final contraceptionHistory = p.reproductiveHistory.contraceptionHistory;
    for (var i = 0; i < contraceptionHistory.length; i++) {
      final c = contraceptionHistory[i];
      entries.add(
        _TimelineEntry(
          date: c.date,
          kind: _EntryKind.contraception,
          title: 'Protection Method — ${c.method}',
          subtitle: c.note ?? 'Method logged',
          color: AppColors.primary,
          emoji: '🛡️',
          listIndex: i,
        ),
      );
    }

    for (var i = 0; i < p.eligibilityHistory.length; i++) {
      final ec = p.eligibilityHistory[i];
      final safeCount = ec.results.where((r) => r.category == 1).length;
      entries.add(
        _TimelineEntry(
          date: ec.date,
          kind: _EntryKind.eligibility,
          title: 'Eligibility Check — ${ec.conditions.length} condition(s)',
          subtitle: ec.conditions.isEmpty
              ? '$safeCount of ${ec.results.length} methods rated "safe to use"'
              : '${ec.conditions.join(", ")} · $safeCount of ${ec.results.length} methods rated "safe to use"',
          color: AppColors.moodYellow,
          emoji: '📝',
          listIndex: i,
        ),
      );
    }

    for (var i = 0; i < p.diaryEntries.length; i++) {
      final d = p.diaryEntries[i];
      final tags = d.symptomTags.isEmpty ? '' : d.symptomTags.join(', ');
      entries.add(
        _TimelineEntry(
          date: d.date,
          kind: _EntryKind.diary,
          title: d.mood != null && d.mood!.isNotEmpty
              ? 'Journal Entry — ${d.mood}'
              : 'Journal Entry',
          subtitle: tags.isEmpty ? d.text : '$tags · ${d.text}',
          color: AppColors.accent,
          emoji: '📔',
          listIndex: i,
        ),
      );
    }

    for (var i = 0; i < p.conversationLog.length; i++) {
      final e = p.conversationLog[i];
      entries.add(
        _TimelineEntry(
          date: e.timestamp,
          kind: _EntryKind.conversation,
          title: e.role == 'user' ? 'You said' : 'Saheli AI',
          subtitle: e.message,
          color: AppColors.accent,
          emoji: e.role == 'user' ? '💬' : '🤖',
          listIndex: i,
        ),
      );
    }

    // Cycle logs come from CycleProvider's dailyLogs map, keyed by date
    // string. Each day's log can carry a period flag/intensity, a mood,
    // and/or a list of symptoms -- each present field becomes its own
    // timeline entry so the diary reads naturally (e.g. "Period Flow:
    // Medium" on one line, "Mood: Anxious" on another, same day).
    dailyLogs.forEach((key, log) {
      final date = _parseDateKey(key);
      if (date == null) return;

      final isPeriodDay = log.isPeriodDay == true;
      final flowIntensity = log.flowIntensity as String?;
      final mood = log.mood as String?;
      final symptoms = (log.symptoms as List?)?.cast<String>() ?? const [];

      if (isPeriodDay || (flowIntensity != null && flowIntensity.isNotEmpty)) {
        entries.add(
          _TimelineEntry(
            date: date,
            kind: _EntryKind.cycle,
            title:
                'Period Flow${flowIntensity != null ? ' — $flowIntensity' : ''}',
            subtitle: isPeriodDay ? 'Logged as a period day' : 'Flow logged',
            color: AppColors.periodRed,
            emoji: '🩸',
            dateKey: key,
            cycleField: 'period',
          ),
        );
      }

      if (mood != null && mood.isNotEmpty) {
        entries.add(
          _TimelineEntry(
            date: date,
            kind: _EntryKind.cycle,
            title: 'Mood — $mood',
            subtitle: 'Logged from your cycle calendar',
            color: AppColors.moodYellow,
            emoji: '🙂',
            dateKey: key,
            cycleField: 'mood',
          ),
        );
      }

      if (symptoms.isNotEmpty) {
        entries.add(
          _TimelineEntry(
            date: date,
            kind: _EntryKind.cycle,
            title: 'Symptoms logged',
            subtitle: symptoms.join(', '),
            color: AppColors.symptomOrange,
            emoji: '📋',
            dateKey: key,
            cycleField: 'symptoms',
          ),
        );
      }
    });

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final cycle = context.watch<CycleProvider>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _manualRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const ProfileSyncBadge(),
                      const SizedBox(height: 20),
                      _buildStatsGrid(_profile!, cycle),
                      const SizedBox(height: 20),
                      _buildTabs(),
                      const SizedBox(height: 16),
                      AppSwitcher(
                        tabKey: _activeTab,
                        child: _activeTab == 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _buildTimelineTab(_profile!, cycle),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _buildProfileTab(_profile!),
                              ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ---------------- Header ----------------

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'My ',
                    style: AppTextStyles.serif(
                      size: 22,
                      weight: FontWeight.w600,
                      color: AppColors.accent,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                  TextSpan(
                    text: 'Diary',
                    style: AppTextStyles.serif(
                      size: 22,
                      weight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        GestureDetector(
          // Spins while the account is actually being re-checked, so the
          // button visibly reacts even when data hasn't changed.
          onTap: _manualRefresh,
          child: Container(
            // Keep clear of the fixed language pill pinned top-right.
            margin: const EdgeInsets.only(right: 96),
            child: _refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.refresh,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
          ),
        ),
      ],
    );
  }

  // ---------------- Stats ----------------

  Widget _buildStatsGrid(HealthProfile p, CycleProvider cycle) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                '${p.pcosHistory.length}',
                'PCOS checks',
                AppColors.ovulationTeal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                '${p.reproductiveHistory.contraceptionHistory.length}',
                'Methods logged',
                AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                '${cycle.dailyLogs.length}',
                'Cycle entries',
                AppColors.periodRed,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                '${p.eligibilityHistory.length}',
                'Eligibility checks',
                AppColors.moodYellow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                '${p.conversationLog.length}',
                'AI check-ins',
                AppColors.accent,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.serif(size: 22, color: color)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(
              size: 10,
              weight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- Tabs ----------------

  Widget _buildTabs() {
    return Row(
      children: [
        Expanded(child: _tabButton('🕒', 'Timeline', 0, AppColors.primary)),
        const SizedBox(width: 10),
        Expanded(child: _tabButton('📋', 'Profile', 1, AppColors.accent)),
      ],
    );
  }

  Widget _tabButton(String emoji, String label, int index, Color activeColor) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.18)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.6)
                : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.sans(
                size: 13,
                weight: FontWeight.w600,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Timeline tab ----------------

  List<Widget> _buildTimelineTab(HealthProfile p, CycleProvider cycle) {
    final entries = _buildTimeline(p, cycle.dailyLogs);

    if (entries.isEmpty) {
      return [_todayDiaryCard(p), _emptyState()];
    }

    // Write today's entry front and center -- a real diary starts with
    // the page you're ON, not your statistics.
    final widgets = <Widget>[_todayDiaryCard(p)];

    // Group by DAY (like a proper diary with per-day pages), newest
    // first. Each group gets a friendly header: Today / Yesterday /
    // weekday, so the history reads like dated pages.
    final grouped = <String, List<_TimelineEntry>>{};
    final dayOrder = <DateTime>[];
    for (final e in entries) {
      final key = '${e.date.year}-${e.date.month}-${e.date.day}';
      if (!grouped.containsKey(key)) dayOrder.add(e.date);
      grouped.putIfAbsent(key, () => []).add(e);
    }

    for (final date in dayOrder) {
      final items = grouped['${date.year}-${date.month}-${date.day}']!;
      widgets.add(_dayHeader(date));
      for (final item in items) {
        widgets.add(_timelineTile(item));
      }
      widgets.add(const SizedBox(height: 10));
    }

    return widgets;
  }

  /// Quick access to writing today's story: shows what's already on
  /// today's page and opens the (existing) diary entry dialog.
  Widget _todayDiaryCard(HealthProfile p) {
    final now = DateTime.now();
    final todaysCount = p.diaryEntries.where((e) {
      return e.date.year == now.year &&
          e.date.month == now.month &&
          e.date.day == now.day;
    }).length;

    final status = todaysCount == 0
        ? tr("Nothing written yet today")
        : tr(
            todaysCount == 1
                ? '1 story written today'
                : '$todaysCount stories written today',
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Text('📖', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr("Today's Diary"),
                  style: AppTextStyles.serif(
                    size: 16,
                    weight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: AppTextStyles.sans(
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showDiaryEntryDialog(context, onSaved: _load),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✍️', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(
                    tr('Write'),
                    style: AppTextStyles.sans(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;

    final md = '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';
    final label = that == today
        ? md
        : diff == 1
        ? '${tr('Yesterday')} · $md'
        : '${_weekdays[d.weekday - 1]}, $md';

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          if (that == today)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsetsDirectional.only(end: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tr('Today'),
                style: AppTextStyles.sans(
                  size: 10,
                  weight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.sans(
                size: 12.5,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineTile(_TimelineEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: e.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: e.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(e.emoji, style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: AppTextStyles.sans(size: 13, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  e.subtitle,
                  style: AppTextStyles.sans(
                    size: 11,
                    color: AppColors.textSecondary,
                  ).copyWith(height: 1.4),
                ),
                const SizedBox(height: 6),
                // The day header above the tile already carries the
                // date; show only the time of day when it's known.
                if (!(e.date.hour == 0 && e.date.minute == 0))
                  Text(
                    '${e.date.hour % 12 == 0 ? 12 : e.date.hour % 12}:${e.date.minute.toString().padLeft(2, '0')} ${e.date.hour >= 12 ? 'pm' : 'am'}',
                    style: AppTextStyles.sans(
                      size: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // Per-entry delete: removes exactly THIS row from your records
          // (keeps the timeline self-managing -- a typo'd AI turn, an old
          // check, or a mistyped mood can be cleaned out on the spot).
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Delete this entry',
            onPressed: () => _confirmAndDeleteEntry(e),
            icon: const Icon(Icons.delete_outline),
            color: AppColors.textSecondary,
            iconSize: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeleteEntry(_TimelineEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete this entry?',
          style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
        ),
        content: Text(
          '"${e.title}" will be permanently removed from your diary. '
          "This can't be undone.",
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
            child: const Text(
              'Delete',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    HealthProfile? updated;
    switch (e.kind) {
      case _EntryKind.pcos:
        updated = await _service.removePcosCheckAt(e.listIndex ?? -1);
        break;
      case _EntryKind.contraception:
        updated = await _service.removeContraceptionAt(e.listIndex ?? -1);
        break;
      case _EntryKind.eligibility:
        updated = await _service.removeEligibilityCheckAt(e.listIndex ?? -1);
        break;
      case _EntryKind.diary:
        updated = await _service.removeDiaryEntryAt(e.listIndex ?? -1);
        break;
      case _EntryKind.conversation:
        updated = await _service.removeConversationAt(e.listIndex ?? -1);
        break;
      case _EntryKind.cycle:
        final date = _parseDateKey(e.dateKey!);
        if (date != null) {
          context.read<CycleProvider>().clearCycleField(date, e.cycleField!);
        }
        break;
    }

    if (!mounted) return;
    if (updated != null) setState(() => _profile = updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: const Text('Entry deleted')));
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          const Text('📖', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          Text(
            'Your diary is empty — for now',
            style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Journal entries, PCOS checks, protection method changes, cycle '
            'logs, and AI check-ins will show up here automatically as you '
            'use the app. Every entry can be deleted from its row.',
            textAlign: TextAlign.center,
            style: AppTextStyles.sans(
              size: 12,
              color: AppColors.textSecondary,
            ).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  // ---------------- Profile tab ----------------

  List<Widget> _buildProfileTab(HealthProfile p) {
    return [
      _profileSection('Demographics', '👤', AppColors.primary, [
        _kv('Age', p.demographics.ageYrs?.toString()),
        _kv(
          'Weight',
          p.demographics.weightKg != null
              ? '${p.demographics.weightKg} kg'
              : null,
        ),
        _kv(
          'Height',
          p.demographics.heightCm != null
              ? '${p.demographics.heightCm} cm'
              : null,
        ),
        _kv('Marital Status', p.demographics.maritalStatus),
      ]),
      const SizedBox(height: 12),
      _profileSection('Lifestyle', '🌿', AppColors.ovulationTeal, [
        _kv('Regular Exercise', _yesNo(p.lifestyle.regularExercise)),
        _kv('Exercise Frequency', p.lifestyle.exerciseFrequency),
        _kv('Diet Quality', p.lifestyle.dietQuality),
        _kv('Frequent Fast Food', _yesNo(p.lifestyle.fastFoodFrequent)),
        _kv(
          'Avg Sleep',
          p.lifestyle.averageSleepHours != null
              ? '${p.lifestyle.averageSleepHours} hrs'
              : null,
        ),
        _kv('Notes', p.lifestyle.notes),
      ]),
      const SizedBox(height: 12),
      _profileSection('Reproductive Health', '🩷', AppColors.periodRed, [
        _kv('Cycle Regularity', p.reproductiveHistory.cycleRegularity),
        _kv(
          'Cycle Length',
          p.reproductiveHistory.cycleLengthDays != null
              ? '${p.reproductiveHistory.cycleLengthDays} days'
              : null,
        ),
        _kv('Current Method', p.reproductiveHistory.currentContraceptionMethod),
      ]),
      const SizedBox(height: 12),
      _profileSection('Wellbeing (self-reported)', '💛', AppColors.moodYellow, [
        _kv(
          'Stress Level (1-5)',
          p.mentalHealth.selfReportedStressLevel?.toString(),
        ),
        _kv('Notes', p.mentalHealth.notes),
        _kv(
          'Last Check-in',
          p.mentalHealth.lastCheckIn != null
              ? _formatDate(p.mentalHealth.lastCheckIn!)
              : null,
        ),
      ]),
      const SizedBox(height: 16),
      Center(
        child: Text(
          'Last updated: ${_formatDate(p.lastUpdated)}',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ),
    ];
  }

  Widget _profileSection(
    String title,
    String emoji,
    Color color,
    List<Widget> rows,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                title,
                style: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
              ),
            ],
          ),
          const Divider(height: 20),
          ...rows,
        ],
      ),
    );
  }

  Widget _kv(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.sans(
                size: 12,
                weight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value ?? 'Not set',
              style: AppTextStyles.sans(
                size: 12,
                color: value == null
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _yesNo(bool? v) {
    if (v == null) return null;
    return v ? 'Yes' : 'No';
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
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $hour:${d.minute.toString().padLeft(2, '0')} $ampm';
  }
}
