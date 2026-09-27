import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color background = Color(0xFFF4ECFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFF8B5FBF);
  static const Color accent = Color(0xFFD988AC);
  static const Color textPrimary = Color(0xFF2A1D3A);
  static const Color textSecondary = Color(0xFF6B5C7A);
  static const Color cardBorder = Color(0xFFE0D3EC);

  // Accent colors for Home screen redesign
  static const Color periodRed = Color(0xFFE05C6E);
  static const Color moodYellow = Color(0xFFE8B84B);
  static const Color symptomOrange = Color(0xFFE8935A);

  // Accent color for Ovulation screen
  static const Color ovulationTeal = Color(0xFF5DCFA0);

  // Extra tones for category tags (contraception, PCOS chips, etc.)
  static const Color sage = Color(0xFF8A9A5B);
  static const Color clay = Color(0xFFB08968);
}

/// Semantic status tones for clinical results.
///
/// These deliberately encode WHO MEC semantics, because the app shows the
/// category next to a recommendation and borrowing a decorative colour for a
/// clinical state is how a "category 4 — unacceptable" ends up looking like a
/// friendly pastel chip:
///   1 accept -> [AppStatus.success]
///   2 caution -> [AppStatus.caution]
///   3 risky -> [AppStatus.risky]
///   4 unacceptable -> [AppStatus.danger]
/// Screening bands reuse the same ramp: low -> success, elevated -> caution,
/// high -> danger. Prefer these over [AppColors.periodRed] and friends for
/// anything a clinician would read.
class AppStatus {
  static const Color success = Color(0xFF1F8A63);
  static const Color caution = Color(0xFFB87415);
  static const Color risky = Color(0xFFD2601F);
  static const Color danger = Color(0xFFC0392F);
  static const Color info = Color(0xFF2F6FB0);

  /// Tinted background for a status chip or callout, sized to sit behind
  /// [success]/[caution]/[risky]/[danger] without reducing text contrast.
  static Color wash(Color tone) => tone.withValues(alpha: 0.10);

  /// Border for a status chip. Slightly stronger than [wash] so a chip still
  /// has a visible edge for users who need it for contrast.
  static Color edge(Color tone) => tone.withValues(alpha: 0.28);

  /// Maps a WHO MEC category (1-4) to its tone. Returns null for anything
  /// outside 1-4 so an unassessed value renders as neutral rather than as a
  /// confident green "accept".
  static Color? fromMecCategory(int? category) {
    switch (category) {
      case 1:
        return success;
      case 2:
        return caution;
      case 3:
        return risky;
      case 4:
        return danger;
      default:
        return null;
    }
  }

  /// Maps a screening band ("low"/"elevated"/"high") to its tone.
  static Color? fromRiskBand(String? band) {
    switch (band) {
      case 'low':
        return success;
      case 'elevated':
        return caution;
      case 'high':
        return danger;
      default:
        return null;
    }
  }
}

/// 4pt spacing scale. Prefer these over literal numbers so vertical rhythm
/// stays consistent between screens.
class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal page gutter.
  static const double gutter = 20;
}

/// Corner radii. The app previously mixed 10/12/14/16/20 between adjacent
/// cards, which reads as sloppy rather than subtle — these four steps are the
/// only corner sizes that should appear in new UI.
class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));
}

/// Soft, brand-tinted elevation.
///
/// Black shadows at full opacity look dirty on a lavender surface, and the app
/// previously used almost none at all (9 across the whole codebase), which is
/// why cards read as flat stickers. These are tinted toward the brand purple
/// and layered rather than harsh.
class AppShadows {
  static List<BoxShadow> sm([bool dark = false]) => [
    BoxShadow(
      color: dark ? const Color(0x40000000) : const Color(0x0F3B2060),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> md([bool dark = false]) => [
    BoxShadow(
      color: dark ? const Color(0x4D000000) : const Color(0x143B2060),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> lg([bool dark = false]) => [
    BoxShadow(
      color: dark ? const Color(0x59000000) : const Color(0x1F3B2060),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];
}

class AppTextStyles {
  static TextStyle serif({
    double size = 20,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.playfairDisplay(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  // ✅ FIXED — removed the accidental `required List<Expanded> children` parameter
  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.normal,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.dmSans(fontSize: size, fontWeight: weight, color: color);
  }

  /// Section eyebrow, e.g. the "TOPICS" label above a group. Letter-spaced and
  /// upper-case is set by the caller; the size here is the floor that stays
  /// legible (the old 10-11px body/subtitle sizes were below comfortable).
  static TextStyle eyebrow({Color color = AppColors.textSecondary}) {
    return GoogleFonts.dmSans(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 1.1,
    );
  }

  /// Body copy with breathing room. Use for answer/paragraph text instead of
  /// appending `.copyWith(height: ...)` at every call site.
  static TextStyle body({double size = 13, Color? color}) {
    return GoogleFonts.dmSans(
      fontSize: size,
      height: 1.55,
      fontWeight: FontWeight.w400,
      color: color ?? AppColors.textSecondary,
    );
  }
}

/// Builds a complete [ThemeData] from a palette.
///
/// Light and dark are generated from the same shape so a component added here
/// can never exist in one mode and silently fall back to a Material default
/// in the other.
ThemeData _buildTheme({
  required bool dark,
  required Color background,
  required Color surface,
  required Color primary,
  required Color accent,
  required Color textPrimary,
  required Color textSecondary,
  required Color border,
  required Color onPrimary,
}) {
  final scheme =
      (dark
              ? ColorScheme.dark(
                  primary: primary,
                  secondary: accent,
                  surface: surface,
                  onSurface: textPrimary,
                  onPrimary: onPrimary,
                )
              : ColorScheme.light(
                  primary: primary,
                  secondary: accent,
                  surface: surface,
                  onSurface: textPrimary,
                  onPrimary: onPrimary,
                ))
          .copyWith(
            surfaceContainerHighest: dark
                ? const Color(0xFF322B3D)
                : const Color(0xFFF7F1FC),
            surfaceContainerLow: dark
                ? const Color(0xFF262031)
                : const Color(0xFFFCFAFE),
            outlineVariant: border,
            surfaceTint: Colors.transparent,
          );

  final dmSans = GoogleFonts.dmSans().fontFamily;

  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: dmSans,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    // Transparent surface tint: Material 3 tints the whole scaffold by the
    // primary colour, which fights the lavender background and makes
    // scrolling content shift colour.
    canvasColor: background,
    splashFactory: InkSparkle.splashFactory,

    textTheme: TextTheme(
      displaySmall: AppTextStyles.serif(size: 30, color: textPrimary),
      headlineMedium: AppTextStyles.serif(size: 24, color: textPrimary),
      headlineSmall: AppTextStyles.serif(size: 21, color: textPrimary),
      titleLarge: AppTextStyles.sans(
        size: 17,
        weight: FontWeight.w700,
        color: textPrimary,
      ),
      titleMedium: AppTextStyles.sans(
        size: 15,
        weight: FontWeight.w600,
        color: textPrimary,
      ),
      bodyLarge: AppTextStyles.sans(size: 15, color: textPrimary),
      bodyMedium: AppTextStyles.body(size: 13, color: textSecondary),
      bodySmall: AppTextStyles.sans(size: 12, color: textSecondary),
      labelLarge: AppTextStyles.sans(
        size: 14,
        weight: FontWeight.w600,
        color: textPrimary,
      ),
      labelSmall: AppTextStyles.sans(
        size: 11,
        weight: FontWeight.w500,
        color: textSecondary,
      ),
    ),

    // --- Cards -----------------------------------------------------------
    // Border-only, because the app is mostly static content; [AppCard] is the
    // shadowed variant for anything that should read as a raised surface.
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: AppColors.cardBorder),
      ),
    ),

    // --- Inputs ----------------------------------------------------------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF262031) : const Color(0xFFFBF7FE),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      hintStyle: AppTextStyles.sans(size: 14, color: textSecondary),
      labelStyle: AppTextStyles.sans(size: 14, color: textSecondary),
      floatingLabelStyle: AppTextStyles.sans(
        size: 13,
        weight: FontWeight.w600,
        color: primary,
      ),
      errorStyle: AppTextStyles.sans(size: 12, color: AppStatus.danger),
      border: _inputBorder(border),
      enabledBorder: _inputBorder(border),
      focusedBorder: _inputBorder(primary, width: 1.6),
      errorBorder: _inputBorder(AppStatus.danger, width: 1.4),
      focusedErrorBorder: _inputBorder(AppStatus.danger, width: 1.6),
      disabledBorder: _inputBorder(
        dark ? const Color(0xFF322B3D) : const Color(0xFFEDE4F5),
      ),
    ),

    // --- Buttons ---------------------------------------------------------
    // No Material elevation: a raised filled button on a soft surface looks
    // dated, and the app already has its own [PillButton] for hero actions.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: dark
            ? const Color(0xFF3A3345)
            : const Color(0xFFDFD2EC),
        disabledForegroundColor: textSecondary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: AppTextStyles.sans(size: 15, weight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: AppTextStyles.sans(size: 15, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        side: BorderSide(color: primary.withValues(alpha: 0.5), width: 1.4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        textStyle: AppTextStyles.sans(size: 15, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(0, 44),
        textStyle: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.serif(size: 20, color: textPrimary),
      iconTheme: IconThemeData(color: textPrimary),
    ),

    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

    chipTheme: ChipThemeData(
      backgroundColor: dark ? const Color(0xFF322B3D) : const Color(0xFFF3EBFB),
      side: BorderSide(color: border),
      labelStyle: AppTextStyles.sans(
        size: 12,
        weight: FontWeight.w600,
        color: textPrimary,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
      titleTextStyle: AppTextStyles.serif(size: 19, color: textPrimary),
      contentTextStyle: AppTextStyles.body(size: 14, color: textSecondary),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: surface,
      elevation: 0,
      showDragHandle: true,
      dragHandleColor: border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF3A3345) : AppColors.textPrimary,
      contentTextStyle: AppTextStyles.sans(size: 14, color: surface),
      actionTextColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: primary,
      titleTextStyle: AppTextStyles.sans(
        size: 15,
        weight: FontWeight.w600,
        color: textPrimary,
      ),
      subtitleTextStyle: AppTextStyles.sans(size: 13, color: textSecondary),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: border,
      circularTrackColor: border,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: primary,
      inactiveTrackColor: border,
      thumbColor: primary,
      overlayColor: primary.withValues(alpha: 0.12),
    ),

    // The app supplies its own custom nav bar, but keep the Material one on
    // token so a future screen that uses NavigationBar matches the app.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primary.withValues(alpha: 0.14),
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(
        AppTextStyles.sans(size: 11, weight: FontWeight.w600),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1.2}) {
  return OutlineInputBorder(
    borderRadius: AppRadius.brMd,
    borderSide: BorderSide(color: color, width: width),
  );
}

ThemeData buildLightTheme() {
  return _buildTheme(
    dark: false,
    background: AppColors.background,
    surface: AppColors.surface,
    primary: AppColors.primary,
    accent: AppColors.accent,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    border: AppColors.cardBorder,
    onPrimary: Colors.white,
  );
}

/// Dark palette in the same lavender/pink family as [AppColors], lightened
/// and desaturated just enough to sit on a dark background without glowing.
class AppColorsDark {
  static const Color background = Color(0xFF1E1A26);
  static const Color surface = Color(0xFF2A2433);
  static const Color primary = Color(0xFFB893E0);
  static const Color accent = Color(0xFFE8AFC7);
  static const Color textPrimary = Color(0xFFF2ECFA);
  static const Color textSecondary = Color(0xFFC2B8D1);
  static const Color cardBorder = Color(0xFF3D3548);
}

ThemeData buildDarkTheme() {
  return _buildTheme(
    dark: true,
    background: AppColorsDark.background,
    surface: AppColorsDark.surface,
    primary: AppColorsDark.primary,
    accent: AppColorsDark.accent,
    textPrimary: AppColorsDark.textPrimary,
    textSecondary: AppColorsDark.textSecondary,
    border: AppColorsDark.cardBorder,
    onPrimary: const Color(0xFF1E1A26),
  );
}

/// Kept as an alias so anything still calling the old name compiles.
ThemeData buildAppTheme() => buildLightTheme();
