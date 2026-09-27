import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A fully-rounded "pill" button with a gentle scale-down animation on
/// press. Use [PillButtonStyle.filled] for primary actions (e.g. "Talk
/// to Saheli") and [PillButtonStyle.outline] for secondary ones.
enum PillButtonStyle { filled, outline, soft }

class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final PillButtonStyle style;
  final IconData? icon;
  final Color? color;

  /// Optional override for the label/icon color. Useful for
  /// [PillButtonStyle.filled] on a light background (e.g. a white pill
  /// button on a gradient card) where white text would be unreadable.
  final Color? foregroundColor;

  /// Renders a dimmed, non-interactive button. Prefer this over dropping the
  /// button entirely so a form's primary action doesn't move while a request
  /// is in flight.
  final bool enabled;

  /// 40pt-tall variant for tight rows; the default 48pt meets the minimum
  /// comfortable touch target.
  final bool compact;

  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = PillButtonStyle.filled,
    this.icon,
    this.color,
    this.foregroundColor,
    this.enabled = true,
    this.compact = false,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.enabled;
    final base = widget.color ?? AppColors.primary;

    late final Color background;
    late final Color foreground;
    BoxBorder? border;

    if (!enabled) {
      // Desaturate rather than just fading the whole button: a fully
      // transparent disabled button on a tinted card disappears entirely.
      final grey = dark ? const Color(0xFF3A3345) : const Color(0xFFE6DCF0);
      background = widget.style == PillButtonStyle.filled ? grey : grey;
      foreground = Theme.of(context).colorScheme.onSurfaceVariant;
    } else {
      switch (widget.style) {
        case PillButtonStyle.filled:
          background = base;
          foreground = widget.foregroundColor ?? Colors.white;
        case PillButtonStyle.outline:
          background = Colors.transparent;
          foreground = base;
          border = Border.all(
            color: dark ? base.withValues(alpha: 0.7) : base,
            width: 1.4,
          );
        case PillButtonStyle.soft:
          background = base.withValues(alpha: dark ? 0.22 : 0.14);
          foreground = base;
      }
    }

    final minHeight = widget.compact ? 40.0 : 48.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.75,
            duration: const Duration(milliseconds: 150),
            child: Container(
              constraints: BoxConstraints(minHeight: minHeight),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 16 : 22,
                vertical: widget.compact ? 9 : 12,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.brPill,
                border: border,
                boxShadow: widget.style == PillButtonStyle.filled && enabled
                    ? [
                        BoxShadow(
                          color: base.withValues(alpha: 0.26),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: widget.compact ? 16 : 18,
                      color: foreground,
                    ),
                    SizedBox(width: widget.compact ? 6 : 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.sans(
                        size: widget.compact ? 13 : 14,
                        weight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
