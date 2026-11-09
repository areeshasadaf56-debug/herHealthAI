import 'package:flutter/material.dart';

/// App-wide animation toolkit.
///
/// Small, single-purpose widgets so screens get consistent motion
/// without each one re-implementing timing/curves:
///   - AppSwitcher: cross-fade + slide when a screen swaps big content
///     (tab changes) instead of cutting instantly.
///   - AppTapScale: gentle press-down feedback for tappable cards/buttons.

/// Cross-fades (with a hairline downward slide) between content blocks
/// keyed by [tabKey]. Use every place a screen does
/// `if (_activeTab == 0) ...a else ...b` so switching feels fluid.
class AppSwitcher extends StatelessWidget {
  const AppSwitcher({
    super.key,
    required this.tabKey,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
  });

  /// Changes when the underlying content logically changes (the tab index).
  final int tabKey;

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // Stack from the top (not centered) so content boxes of different
      // heights align like normal column children did.
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey<int>(tabKey), child: child),
    );
  }
}

/// Press feedback: scales down slightly while the finger is down.
/// WrapGestureDetector-style tap handlers that currently have no visual
/// reaction (cards, primary buttons, chips).
class AppTapScale extends StatefulWidget {
  const AppTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<AppTapScale> createState() => _AppTapScaleState();
}

class _AppTapScaleState extends State<AppTapScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
