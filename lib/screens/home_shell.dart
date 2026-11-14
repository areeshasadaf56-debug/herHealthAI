import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'ovulation_screen.dart';
import 'protection_screen.dart';
import 'pcos_screen.dart';
import 'endo_screen.dart';
import 'learn_screen.dart';
import 'settings_screen.dart';
import 'ai_checkin_screen.dart';

// The app's main shell after sign-in: a bottom nav bar switching between
// the 8 primary tabs (now includes AI Check-in). Each tab's screen is kept
// alive in an IndexedStack so switching tabs doesn't rebuild/reset their state.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  int _tabIndex = 0;

  // Replays a short fade+lift every time the active tab changes, so the
  // state-preserving IndexedStack (which can't cross-fade by itself)
  // still feels animated instead of cutting instantly.
  late final AnimationController _switchController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1.0, // fully "settled" on first build so the app opens visible
  );

  late final Animation<double> _switchAnimation = CurvedAnimation(
    parent: _switchController,
    curve: Curves.easeOutCubic,
  );

  void _changeTab(int index) {
    if (index == _tabIndex) return;
    setState(() => _tabIndex = index);
    _switchController.forward(from: 0);
  }

  /// Navigate to a specific tab by name or index
  void _navigateToTab(String tabName) {
    final tabMap = {
      'cycle': 0,
      'ovulation': 1,
      'protection': 2,
      'pcos': 3,
      'endo': 4,
      'learn': 5,
      'settings': 6,
      'checkin': 7,
    };

    final newIndex = tabMap[tabName] ?? 0;
    _changeTab(newIndex);
  }

  final List<_NavItem> _navItems = [
    const _NavItem(
      icon: Icons.nightlight_round,
      label: 'Cycle',
      shortLabel: 'Cycle',
    ),
    const _NavItem(
      icon: Icons.egg_outlined,
      label: 'Ovulation',
      shortLabel: 'Ovu',
    ),
    const _NavItem(
      icon: Icons.shield_outlined,
      label: 'Protection',
      shortLabel: 'Prot',
    ),
    const _NavItem(
      icon: Icons.bubble_chart_outlined,
      label: 'PCOS',
      shortLabel: 'PCOS',
    ),
    const _NavItem(
      icon: Icons.local_florist_outlined,
      label: 'Endo',
      shortLabel: 'Endo',
    ),
    const _NavItem(
      icon: Icons.menu_book_outlined,
      label: 'Learn',
      shortLabel: 'Learn',
    ),
    const _NavItem(
      icon: Icons.settings_outlined,
      label: 'Settings',
      shortLabel: 'Set',
    ),
    const _NavItem(
      icon: Icons.favorite_rounded,
      label: 'Check-in',
      shortLabel: 'Chat',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Build tabs here in build() so _navigateToTab is available
    final tabs = [
      HomeScreen(onNavigateToTab: _navigateToTab),
      const OvulationScreen(),
      const ProtectionScreen(),
      const PcosScreen(),
      const EndoScreen(),
      const LearnScreen(),
      const SettingsScreen(),
      AiCheckinScreen(onNavigateToTab: _navigateToTab),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        // Task 2.3: content cap. On phones (and anything narrower) the
        // screens keep filling the available width; on tablets/desktop
        // the readable column is centered at 640px instead of
        // stretching edge to edge.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: FadeTransition(
              opacity: Tween<double>(
                begin: 0.55,
                end: 1.0,
              ).animate(_switchAnimation),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.012),
                  end: Offset.zero,
                ).animate(_switchAnimation),
                child: IndexedStack(index: _tabIndex, children: tabs),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SafeArea(
          top: false,
          // Same 640px cap as the body so the nav row doesn't smear one
          // item into every corner of a desktop window.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
                children: List.generate(_navItems.length, (i) {
                  final item = _navItems[i];
                  final active = _tabIndex == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _changeTab(i),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 6,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary.withValues(alpha: 0.10)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedScale(
                                scale: active ? 1.12 : 1.0,
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                child: Icon(
                                  item.icon,
                                  size: 18,
                                  color: active
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.shortLabel,
                                style: AppTextStyles.sans(
                                  size: 7.5,
                                  weight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: active
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String shortLabel;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.shortLabel,
  });
}
