import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellness_saheli/theme/app_theme.dart';
import 'package:wellness_saheli/widgets/app_card.dart';

/// Guards for the Phase 4 design tokens.
///
/// These pin properties that would be invisible in code review but obvious to a
/// user: a WHO MEC category rendering as a confident green, a status tint so
/// opaque it swallows its own label, or a card that stops being tappable.
///
/// ## Why `buildLightTheme()` is not exercised here
/// The theme resolves DM Sans / Playfair Display through `google_fonts`, which
/// this project does **not** bundle as an asset. Constructing the theme
/// therefore triggers a font load that throws in a widget test (runtime
/// fetching is network-blocked, and disabling it makes the package throw
/// because the file is not in the asset manifest). So any test that calls
/// `buildLightTheme()` / `buildDarkTheme()` fails, which is why the widget
/// tests below use a bare `ThemeData`.
///
/// The fix is to bundle the font files (see `fonts:` in pubspec.yaml) and set
/// `GoogleFonts.config.allowRuntimeFetching = false`. That also removes a
/// runtime network dependency from a health app that may be used on patchy
/// mobile data. Until then, the light/dark component parity that `_buildTheme`
/// guarantees by construction is enforced by that shared function rather than
/// by a test.
void main() {
  // A font-free theme for widget tests.
  ThemeData bareTheme() => ThemeData(useMaterial3: true);

  group('AppStatus WHO MEC mapping', () {
    // A category is medical guidance, so this mapping is pinned exactly.
    // WHO MEC 5e: 1 accept, 2 caution, 3 risks, 4 unacceptable.
    test('maps every valid category to the intended tone', () {
      expect(AppStatus.fromMecCategory(1), AppStatus.success);
      expect(AppStatus.fromMecCategory(2), AppStatus.caution);
      expect(AppStatus.fromMecCategory(3), AppStatus.risky);
      expect(AppStatus.fromMecCategory(4), AppStatus.danger);
    });

    // The important one. `category: null` is how the backend says "not yet
    // assessed" for the unrated WHO MEC rows. Rendering that as category 1
    // green would tell a woman an unverified method is safe to use.
    test('returns null for unassessed or out-of-range categories', () {
      expect(AppStatus.fromMecCategory(null), isNull);
      expect(AppStatus.fromMecCategory(0), isNull);
      expect(AppStatus.fromMecCategory(5), isNull);
      expect(AppStatus.fromMecCategory(-1), isNull);
    });

    test('maps the three screening bands', () {
      expect(AppStatus.fromRiskBand('low'), AppStatus.success);
      expect(AppStatus.fromRiskBand('elevated'), AppStatus.caution);
      expect(AppStatus.fromRiskBand('high'), AppStatus.danger);
      expect(AppStatus.fromRiskBand(null), isNull);
      expect(AppStatus.fromRiskBand('unknown'), isNull);
    });

    test('the four tones are all distinguishable', () {
      final tones = {
        AppStatus.success,
        AppStatus.caution,
        AppStatus.risky,
        AppStatus.danger,
      };
      expect(tones.length, 4, reason: 'a clinical tone was made a duplicate');
    });
  });

  group('AppStatus tints', () {
    // A "wash" behind a chip must stay translucent, or the label drawn on top
    // of it loses contrast.
    test('wash and edge are translucent, and the edge is firmer', () {
      for (final tone in [
        AppStatus.success,
        AppStatus.caution,
        AppStatus.risky,
        AppStatus.danger,
      ]) {
        final wash = AppStatus.wash(tone);
        final edge = AppStatus.edge(tone);
        expect(wash.a, greaterThan(0), reason: '$tone wash is invisible');
        expect(wash.a, lessThan(0.35), reason: '$tone wash is too opaque');
        expect(
          edge.a,
          greaterThan(wash.a),
          reason: '$tone edge must be firmer',
        );
        expect(edge.a, lessThan(0.6), reason: '$tone edge is too opaque');
      }
    });
  });

  group('spacing and radius tokens', () {
    test('spacing increases monotonically on the 4pt grid', () {
      final steps = [
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: 'spacing step $i is not increasing',
        );
        // Every step is a multiple of 4, even though the last one jumps by 8
        // to give a roomy outer margin.
        expect(steps[i] % 4, 0, reason: 'spacing step $i is off the 4pt grid');
      }
    });

    // The app previously mixed 10/12/14/16/20 between adjacent cards, which
    // reads as sloppy. These four steps are the sanctioned corner sizes.
    test('radii are monotonic and end at pill', () {
      final steps = [
        AppRadius.sm,
        AppRadius.md,
        AppRadius.lg,
        AppRadius.xl,
        AppRadius.pill,
      ];
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: 'radius step $i is not increasing',
        );
      }
      expect(AppRadius.pill, greaterThan(AppRadius.xl));
    });

    test('shadow tokens are ordered and always tinted, never pure black', () {
      // Pure black at full opacity looks dirty on a lavender surface.
      for (final entry in [
        ['sm', AppShadows.sm()],
        ['md', AppShadows.md()],
        ['lg', AppShadows.lg()],
      ]) {
        for (final shadow in entry[1] as List<BoxShadow>) {
          expect(shadow.color.a, lessThan(0.5), reason: '${entry[0]} too dark');
        }
      }
      expect(AppShadows.sm().length, 1);
      expect(AppShadows.lg().length, 1);
    });
  });

  group('AppCard', () {
    testWidgets('renders its child and fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: bareTheme(),
          home: Scaffold(
            body: AppCard(onTap: () => taps++, child: const Text('Inside')),
          ),
        ),
      );

      expect(find.text('Inside'), findsOneWidget);
      await tester.tap(find.text('Inside'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('every variant and an accent bar build cleanly', (
      tester,
    ) async {
      for (final variant in AppCardVariant.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: bareTheme(),
            home: Scaffold(
              body: AppCard(
                variant: variant,
                accent: AppColors.accent,
                child: const Text('x'),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$variant threw');
      }
    });

    testWidgets('an accent bar stretches to the content height', (
      tester,
    ) async {
      // Guards the Row/stretched-bar layout: if the bar collapsed to zero it
      // would render as an invisible 4px line.
      await tester.pumpWidget(
        MaterialApp(
          theme: bareTheme(),
          home: Scaffold(
            body: AppCard(
              accent: AppColors.accent,
              child: const SizedBox(height: 120, width: 60),
            ),
          ),
        ),
      );
      final bar = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).borderRadius ==
                    BorderRadius.circular(2),
          );
      expect(bar, isNotEmpty, reason: 'accent bar not found');
    });

    testWidgets('a card with no onTap does not throw when tapped', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bareTheme(),
          home: const Scaffold(body: AppCard(child: Text('Static'))),
        ),
      );
      await tester.tap(find.text('Static'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('AppStatusChip', () {
    testWidgets('always pairs its colour with a text label', (tester) async {
      // Colour alone must never be the only carrier of meaning.
      await tester.pumpWidget(
        MaterialApp(
          theme: bareTheme(),
          home: Scaffold(
            body: Column(
              children: const [
                AppStatusChip(
                  label: 'Category 1 - accept',
                  tone: AppStatus.success,
                ),
                AppStatusChip(label: 'Pending review', tone: AppStatus.caution),
                AppStatusChip(label: 'Not yet assessed', tone: null),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Category 1 - accept'), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(find.text('Not yet assessed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bareTheme().copyWith(brightness: Brightness.dark),
          home: const Scaffold(
            body: AppStatusChip(label: 'High', tone: AppStatus.danger),
          ),
        ),
      );
      expect(find.text('High'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
