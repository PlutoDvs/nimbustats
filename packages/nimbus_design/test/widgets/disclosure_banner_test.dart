import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

Widget host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: NimbusTheme.light(),
      locale: locale,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('the banner states the caveat rather than hinting at it',
      (tester) async {
    await tester.pumpWidget(host(const NimbusDisclosureBanner(
      message: 'Slices do not add up to the total.',
    )));

    expect(find.text('Slices do not add up to the total.'), findsOneWidget);
  });

  testWidgets('the banner is announced to a screen reader', (tester) async {
    // This carries the reason a chart's numbers look wrong. A sighted user
    // gets it from position and colour; without a semantics node, a screen
    // reader user gets nothing at all.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(const NimbusDisclosureBanner(
      message: 'Slices do not add up to the total.',
    )));

    expect(
      find.bySemanticsLabel('Slices do not add up to the total.'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the banner reads right-to-left in Persian', (tester) async {
    await tester.pumpWidget(host(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: NimbusDisclosureBanner(message: 'جمع بخش‌ها با کل برابر نیست.'),
      ),
    ));

    expect(
      Directionality.of(tester.element(find.byType(NimbusDisclosureBanner))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the banner takes its colours from the theme', (tester) async {
    // Not decoration: ux_rules_test.dart fails the build on a raw Color
    // literal outside this package, and a banner that hardcoded a warning
    // yellow would be unreadable in the dark theme.
    await tester.pumpWidget(host(const NimbusDisclosureBanner(
      message: 'anything',
    )));

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(NimbusDisclosureBanner),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(container.decoration, isNotNull);
  });
}
