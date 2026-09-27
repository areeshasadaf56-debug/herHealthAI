import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppCardVariant {
  /// Border plus a soft brand-tinted shadow. For anything that should read as
  /// a raised, tappable surface. This is the default.
  elevated,

  /// Border only, no shadow. For dense static content where a shadow would
  /// add noise — a stack of these should still look deliberate.
  flat,

  /// Tinted fill, no border. For nested or secondary content that should
  /// recede rather than compete.
  tinted,
}

/// The app's standard content surface.
///
/// Replaces the ad-hoc `Container` + `BoxDecoration` + `Border.all` pattern
/// that appeared 134 times across `lib/`, which is where the inconsistent
/// corner sizes and missing shadows came from. Going through one widget means
/// radius, elevation, ink clipping, press feedback and dark mode stay in sync
/// across every screen.
///
/// Keep it presentation-only: pass an [onTap] and it handles the ripple and
/// press scale for you.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final AppCardVariant variant;
  final Color? accent;
  final Color? color;
  final double radius;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.variant = AppCardVariant.elevated,
    this.accent,
    this.color,
    this.radius = AppRadius.md,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);

    final Color surface = color ?? Theme.of(context).colorScheme.surface;
    final Color borderColor =
        border?.top.color ?? Theme.of(context).colorScheme.outlineVariant;

    // A leading accent bar, for cards that lead with a category colour
    // (e.g. a WHO MEC category or a cycle phase).
    final showAccentBar = accent != null && variant != AppCardVariant.tinted;

    Widget content = Padding(padding: padding, child: child);

    if (showAccentBar) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: content),
        ],
      );
    }

    BoxDecoration decoration;
    switch (variant) {
      case AppCardVariant.elevated:
        decoration = BoxDecoration(
          color: surface,
          borderRadius: shape,
          border: border ?? Border.all(color: borderColor),
          boxShadow: AppShadows.sm(dark),
        );
      case AppCardVariant.flat:
        decoration = BoxDecoration(
          color: surface,
          borderRadius: shape,
          border: border ?? Border.all(color: borderColor),
        );
      case AppCardVariant.tinted:
        decoration = BoxDecoration(
          color: color ?? surface.withValues(alpha: dark ? 0.55 : 0.6),
          borderRadius: shape,
          border: border,
        );
    }

    // The shadow lives on an outer Container while the `Material` provides the
    // ink layer, so the ripple is clipped to the rounded corners instead of
    // spilling into a square.
    Widget body = DecoratedBox(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: shape,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: shape, child: content),
      ),
    );

    if (onTap == null) {
      return body;
    }

    // A small press-scale gives tactile feedback that a ripple alone doesn't,
    // matching the feel of the existing [PillButton].
    return _PressableScale(onTap: onTap!, child: body);
  }
}

class _PressableScale extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _PressableScale({required this.onTap, required this.child});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// An upper-case, letter-spaced section label with an optional trailing
/// action, e.g. `TOPICS` / `Your history` / `See all`.
///
/// Screens were hand-rolling this in a dozen slightly different ways, usually
/// at 10-11px in flat grey, which is too small to scan comfortably.
class AppSectionHeader extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppSectionHeader({
    super.key,
    required this.label,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    final title = Text(label.toUpperCase(), style: AppTextStyles.eyebrow());

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.sans(
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A small pill label for a state — method category, screening band,
/// provenance, selection status.
///
/// Wraps the colour ramp in [AppStatus] so a clinical state is never carried
/// by a decorative accent, and always pairs the colour with a text label
/// rather than relying on hue alone.
class AppStatusChip extends StatelessWidget {
  final String label;
  final Color? tone;
  final IconData? icon;
  final bool dense;

  const AppStatusChip({
    super.key,
    required this.label,
    this.tone,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effective = tone ?? scheme.primary;
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? effective.withValues(alpha: 0.95)
        : effective;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: AppStatus.wash(effective),
        borderRadius: AppRadius.brPill,
        border: Border.all(color: AppStatus.edge(effective)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTextStyles.sans(
              size: dense ? 10.5 : 11.5,
              weight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
