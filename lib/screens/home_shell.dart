import 'package:flutter/material.dart';
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

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;

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
    setState(() => _tabIndex = newIndex);
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: IndexedStack(index: _tabIndex, children: tabs),
          ),
        ),
      ),
      bottomNavigationBar: _buildNavBar(context),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    // A soft upward shadow instead of a hard 1px rule: the bar reads as
    // floating above the content rather than as a line drawn across it.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            color: dark ? const Color(0x59000000) : const Color(0x143B2060),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      // Material so each destination can show a real ink ripple.
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          // A bare `Center` expands to fill ALL the height the Scaffold
          // offers the bottomNavigationBar slot, which leaves the body with
          // zero height and renders the page blank. A `Row` derives its
          // height from its children, so it cannot starve the body.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Row(
                      children: List.generate(_navItems.length, (i) {
                        final item = _navItems[i];
                        return Expanded(
                          child: _NavDestination(
                            item: item,
                            active: _tabIndex == i,
                            onTap: () => setState(() => _tabIndex = i),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination in the bottom bar.
///
/// The active state is a soft pill behind the icon rather than a colour swap
/// alone, which keeps the current tab locatable at a glance and gives the bar
/// a focus colour for users who can't rely on the lavender/grey contrast.
class _NavDestination extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavDestination({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = active ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: AppRadius.brPill,
                ),
                child: Icon(item.icon, size: 20, color: tone),
              ),
              const SizedBox(height: 3),
              Text(
                item.shortLabel,
                style: AppTextStyles.sans(
                  size: 9.5,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  color: tone,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
