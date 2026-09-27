import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Navigation between the app's top-level destinations.
///
/// Every other widget test in this package reaches its screen with
/// `initialLocation`, which is how the app shipped for two phases with
/// `/settings` registered, tested, and unreachable by a human being. These
/// tests deliberately never pass `initialLocation`: they start where a real
/// launch starts and tap their way, so an orphaned destination fails here.
/// A destination's label, scoped to the nav bar.
///
/// Unscoped, `find.text('Settings')` also matches the settings screen's own
/// app-bar title once that tab is open, so the finder has to say which one it
/// means rather than depending on which screen happens to be showing.
Finder navItem(String label) => find.descendant(
      of: find.byKey(const Key('nav-bar')),
      matching: find.text(label),
    );

void main() {
  testWidgets('the shell offers home, analytics and settings', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('nav-bar')), findsOneWidget);
    expect(navItem('Home'), findsOneWidget);
    expect(navItem('Analytics'), findsOneWidget);
    expect(navItem('Settings'), findsOneWidget);
  });

  testWidgets('settings is reachable by tapping, with no deep link',
      (tester) async {
    // The regression test for the hole this shell closes. Settings, and the
    // category and tag managers reachable only from it, were dead to a user
    // from Phase 1 until now -- while five settings tests passed, because
    // every one of them deep-linked past the missing entry point.
    await pumpApp(tester);
    expect(find.byKey(const Key('settings-theme')), findsNothing);

    await tester.tap(navItem('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-theme')), findsOneWidget);
  });

  testWidgets('tapping analytics shows the analytics screen', (tester) async {
    await pumpApp(tester);

    await tester.tap(navItem('Analytics'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analytics-screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the destination the user is on is the selected one',
      (tester) async {
    // A nav bar that never moves its selection is worse than none: it tells
    // the user they did not go anywhere.
    await pumpApp(tester);
    NavigationBar bar() =>
        tester.widget<NavigationBar>(find.byKey(const Key('nav-bar')));
    expect(bar().selectedIndex, 0);

    await tester.tap(navItem('Analytics'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 1);

    await tester.tap(navItem('Settings'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 2);
  });

  testWidgets('going back to home reselects home', (tester) async {
    await pumpApp(tester);
    await tester.tap(navItem('Analytics'));
    await tester.pumpAndSettle();

    await tester.tap(navItem('Home'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NavigationBar>(find.byKey(const Key('nav-bar')))
          .selectedIndex,
      0,
    );
    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);
  });

  testWidgets('a full-screen task is pushed over the shell, not inside it',
      (tester) async {
    // Adding an expense owns the whole screen -- it already carries its own
    // bottom bar for the save action, and a nav bar underneath would offer an
    // escape hatch that silently discards the draft.
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('tx-add-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav-bar')), findsNothing);
  });

  testWidgets('the nav bar is right-to-left in Persian', (tester) async {
    await pumpApp(tester, locale: const Locale('fa'));

    expect(
      Directionality.of(tester.element(find.byKey(const Key('nav-bar')))),
      TextDirection.rtl,
    );
  });

  testWidgets('the add button is on home only', (tester) async {
    // It lives on the shell's Scaffold so it rises above the "saved"
    // snackbar; being there must not put it on every destination.
    final fab = find.byKey(const Key('tx-add-fab'));
    await pumpApp(tester);
    expect(fab, findsOneWidget);

    for (final route in ['/analytics', '/settings']) {
      await pumpApp(tester, initialLocation: route);
      expect(fab, findsNothing, reason: route);
    }
  });
}
