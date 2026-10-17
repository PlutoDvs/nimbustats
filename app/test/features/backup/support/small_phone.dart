import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 360 × 640 phone at twice the text size, reset when the test ends.
void useSmallPhoneLargeText(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(360, 640)
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
