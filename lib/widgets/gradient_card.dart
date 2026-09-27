import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A soft, rounded card with a gradient background and faint
/// decorative circles — the same visual language used on the AI
/// welcome card, reused anywhere a "hero" surface is needed (streak
/// banners, phase highlight, check-in prompts).
///
/// Stays presentation-only: [onTap] is optional, and when supplied this widget
/// handles the press scale and ink ripple for you. Wrap it in your own
/// `GestureDetector` only if you need behaviour a tap doesn't cover.
class GradientCard extends StatelessWidget {
  final Widget child;
  final List<Color>? colors;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool showDecoration;
  final VoidCallback? onTap;
  final Widget? trailing;

  const GradientCard({
    super.key,
    required this.child,
    this.colors,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius = AppRadius.lg,
    this.showDecoration = true,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = colors ?? [AppColors.primary, AppColors.accent];
    final radius = BorderRadius.circular(borderRadius);

    final Widget body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors
              .map((c) => dark ? c.withValues(alpha: 0.34) : c)
              .toList(),
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: dark ? 0.28 : 0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (showDecoration) ...[
              Positioned(
                top: -36,
                right: -36,
                child: _decorativeCircle(120, dark),
              ),
              Positioned(
                bottom: -28,
                left: -28,
                child: _decorativeCircle(100, dark),
              ),
            ],
            // A diagonal sheen keeps the flat gradient from looking like a
            // two-colour rectangle, without introducing a new hue.
            if (showDecoration)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withValues(alpha: dark ? 0.10 : 0.16),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: trailing == null
                  ? child
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: child),
                        const SizedBox(width: AppSpacing.sm),
                        trailing!,
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return body;

    return _GradientCardTap(onTap: onTap!, child: body);
  }

  Widget _decorativeCircle(double size, bool dark) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: dark ? 0.05 : 0.09),
    ),
  );
}

class _GradientCardTap extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _GradientCardTap({required this.onTap, required this.child});

  @override
  State<_GradientCardTap> createState() => _GradientCardTapState();
}

class _GradientCardTapState extends State<_GradientCardTap> {
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
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
