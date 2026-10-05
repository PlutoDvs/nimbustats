import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_presets.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  final swatches =
      NimbusColors.categorySwatches.values.map((c) => c.toARGB32()).toSet();

  for (final locale in const [Locale('en'), Locale('fa')]) {
    test('the $locale presets: one of each type, known icons, swatch colours',
        () {
      final presets = trackerPresets(lookupAppLocalizations(locale));

      expect(presets.map((p) => p.type), [
        TrackerType.quantity,
        TrackerType.counter,
        TrackerType.boolean,
        TrackerType.duration,
      ]);
      for (final preset in presets) {
        expect(nimbusIcons.containsKey(preset.iconKey), isTrue,
            reason: '${preset.name}: ${preset.iconKey}');
        expect(swatches, contains(preset.color), reason: preset.name);
      }
      expect(presets.first.perTapValue, 0.25);
    });
  }

  test('the presets are named, and Water measured, in the current language',
      () {
    final en = trackerPresets(lookupAppLocalizations(const Locale('en')));
    final fa = trackerPresets(lookupAppLocalizations(const Locale('fa')));
    expect(en.map((p) => p.name), ['Water', 'Cigarettes', 'Gym', 'Sleep']);
    expect(fa.map((p) => p.name), ['آب', 'سیگار', 'باشگاه', 'خواب']);
    expect(en.first.unit, 'L');
    expect(fa.first.unit, 'لیتر');
  });
}
