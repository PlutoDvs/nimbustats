import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/ui_dump.dart';

/// The lookup `tool/frame_timings.dart` uses to find a button to tap on the
/// device, from `adb shell uiautomator dump` output. A wrong centre taps
/// whatever happens to be there, so it is held to exact coordinates.
void main() {
  /// Nodes in the shape uiautomator writes them, trimmed to the attributes
  /// the lookup reads.
  String dump(String nodes) =>
      "<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>"
      '<hierarchy rotation="0">'
      '<node index="0" text="" class="android.widget.FrameLayout" '
      'package="com.nimbustats.app" content-desc="" bounds="[0,0][1080,2340]">'
      '$nodes'
      '</node></hierarchy>';

  test('finds the centre of the node a screen reader names', () {
    final xml = dump(
      '<node index="1" text="" class="android.widget.Button" '
      'content-desc="Previous month" clickable="true" '
      'bounds="[21,357][147,483]" />'
      '<node index="2" text="" class="android.widget.Button" '
      'content-desc="Next month" clickable="true" '
      'bounds="[933,357][1059,483]" />',
    );

    expect(centresOf(xml, 'Previous month'), [(x: 84, y: 420)]);
    expect(centresOf(xml, 'Next month'), [(x: 996, y: 420)]);
  });

  test('matches a visible text as well as a description', () {
    final xml = dump(
      '<node index="1" text="Breakdown" class="android.view.View" '
      'content-desc="" bounds="[200,250][400,330]" />',
    );

    expect(centresOf(xml, 'Breakdown'), [(x: 300, y: 290)]);
  });

  test('matches one line of a description merged from several', () {
    // Flutter merges a control's semantics into one node, joined by newlines,
    // which uiautomator writes as &#10;.
    final xml = dump(
      '<node index="1" text="" class="android.view.View" '
      'content-desc="Spending by category&#10;Card options" '
      'bounds="[0,600][1080,700]" />',
    );

    expect(centresOf(xml, 'Card options'), [(x: 540, y: 650)]);
    expect(centresOf(xml, 'Card'), isEmpty, reason: 'whole lines only');
  });

  test('decodes entities before comparing', () {
    final xml = dump(
      '<node index="1" text="" class="android.view.View" '
      'content-desc="Groceries &amp; rent" bounds="[0,0][100,100]" />',
    );

    expect(centresOf(xml, 'Groceries & rent'), [(x: 50, y: 50)]);
  });

  test('returns every match, and none when nothing matches', () {
    // The caller decides what ambiguity means; guessing one of two nodes is
    // how a tap lands on the wrong button.
    final xml = dump(
      '<node index="1" text="" content-desc="Pin to dashboard" '
      'bounds="[0,0][100,100]" />'
      '<node index="2" text="" content-desc="Pin to dashboard" '
      'bounds="[0,200][100,300]" />',
    );

    expect(centresOf(xml, 'Pin to dashboard'), hasLength(2));
    expect(centresOf(xml, 'Previous month'), isEmpty);
  });
}
