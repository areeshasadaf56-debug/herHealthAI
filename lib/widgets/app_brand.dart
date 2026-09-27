import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

/// The "Wellness _Saheli_" wordmark lockup.
///
/// This exact treatment was copy-pasted into seven screens (`home`, `endo`,
/// `learn`, `ovulation`, `pcos`, `protection`, `sign_in`), each with slightly
/// different sizes and spacing. It lives here now so the one piece of brand
/// identity every screen shares can only be changed in one place.
class AppWordmark extends StatelessWidget {
  final double size;
  final bool centered;
  final String? subtitle;
  final Widget? trailing;

  const AppWordmark({
    super.key,
    this.size = 22,
    this.centered = false,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final lockup = Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'Wellness ',
          style: AppTextStyles.serif(
            size: size,
            color: AppColors.accent,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
        Text(
          'Saheli',
          style: AppTextStyles.serif(size: size, color: AppColors.primary),
        ),
      ],
    );

    Widget content = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        lockup,
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: AppTextStyles.sans(size: 13, color: AppColors.textSecondary),
          ),
        ],
      ],
    );

    if (trailing == null) return content;

    return Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: content),
        trailing!,
      ],
    );
  }
}

/// The app's logo mark — a crescent moon and a sprouting plant on a night sky,
/// for cycles and growth.
///
/// The asset already carries its own dark circular background, so this is shown
/// as-is rather than dropped into a tinted disc, which is what made the
/// previous flower-emoji badge look pasted on.
class AppLogoMark extends StatelessWidget {
  final double size;

  /// Draws a soft brand-tinted halo behind the mark, for placing it directly on
  /// the page background.
  final bool halo;

  const AppLogoMark({super.key, this.size = 64, this.halo = true});

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      'assets/images/logo.svg',
      width: size,
      height: size,
      semanticsLabel: 'Wellness Saheli',
      // Never let a missing or malformed asset take down the auth screen.
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );

    if (!halo) return mark;

    return Container(
      width: size + 24,
      height: size + 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: mark,
    );
  }
}
