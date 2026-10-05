import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import 'tracker_draft.dart';

/// The four trackers the empty tab offers, named in the current language.
///
/// Colours come from the category swatches rather than literals, so a
/// token-sheet swap recolours them with everything else.
List<TrackerDraft> trackerPresets(AppLocalizations l10n) => [
      TrackerDraft(
        name: l10n.trackerPresetWater,
        iconKey: 'water_drop',
        color: _swatch('blue'),
        type: TrackerType.quantity,
        unit: l10n.trackerPresetWaterUnit,
        perTapValue: 0.25,
      ),
      TrackerDraft(
        name: l10n.trackerPresetCigarettes,
        iconKey: 'smoking_rooms',
        color: _swatch('slate'),
        type: TrackerType.counter,
      ),
      TrackerDraft(
        name: l10n.trackerPresetGym,
        iconKey: 'fitness_center',
        color: _swatch('green'),
        type: TrackerType.boolean,
      ),
      TrackerDraft(
        name: l10n.trackerPresetSleep,
        iconKey: 'bedtime',
        color: _swatch('indigo'),
        type: TrackerType.duration,
      ),
    ];

int _swatch(String name) {
  final color = NimbusColors.categorySwatches[name];
  if (color == null) throw StateError('no category swatch "$name"');
  return color.toARGB32();
}
