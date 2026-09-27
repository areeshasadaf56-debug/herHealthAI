import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellness_saheli/providers/cycle_provider.dart';
import 'package:wellness_saheli/screens/home_screen.dart';
import 'package:wellness_saheli/screens/home_shell.dart';

/// Regression test for the blank-body bug: the `Center` that used to wrap the
/// bottom navigation expanded to fill the whole bottomNavigationBar slot,
/// leaving the Scaffold body with zero height. The page content was built
/// (dozens of widgets) but painted into a 0-height box, so users saw the
/// navigation bar with an empty white area above it.
void main() {
  SharedPreferences.setMockInitialValues({});

  Future<CycleProvider> loggedInProvider(WidgetTester tester) async {
    final provider = CycleProvider();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await provider.login('Test User', userId: '1', token: 'test-token');
    return provider;
  }

  testWidgets('HomeShell body has real height, not zero', (tester) async {
    final provider = await loggedInProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider<CycleProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);

    final body = tester.getSize(find.byType(IndexedStack));
    expect(
      body.height,
      greaterThan(0),
      reason: 'IndexedStack body collapsed to zero height (blank page bug)',
    );

    final home = tester.getSize(find.byType(HomeScreen));
    expect(
      home.height,
      greaterThan(0),
      reason: 'HomeScreen collapsed to zero height (blank page bug)',
    );
  });

  testWidgets('HomeShell navigation bar does not consume the whole screen',
      (tester) async {
    final provider = await loggedInProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider<CycleProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // The nav bar's own SafeArea must stay compact, not expand to fill.
    final nav = find.ancestor(
      of: find.text('Cycle'),
      matching: find.byType(SafeArea),
    );
    final navHeight = tester.getSize(nav.first).height;
    expect(
      navHeight,
      lessThan(200),
      reason: 'Bottom navigation bar is expanding and starving the body',
    );
  });

  testWidgets('All eight tabs are present and the index maps to Cycle',
      (tester) async {
    final provider = await loggedInProvider(tester);

    await tester.pumpWidget(
      ChangeNotifierProvider<CycleProvider>.value(
        value: provider,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.children.length, 8);
    expect(stack.index, 0);
    expect(stack.children.first, isA<HomeScreen>());
  });
}
