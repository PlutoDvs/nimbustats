import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';

/// Hours and minutes, side by side. The add-time sheet and the entry editor
/// both use it.
class TrackerDurationFields extends StatelessWidget {
  const TrackerDurationFields({
    super.key,
    required this.hours,
    required this.minutes,
    required this.keyPrefix,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController hours;
  final TextEditingController minutes;

  /// The fields are keyed `<keyPrefix>-hours` and `<keyPrefix>-minutes`.
  final String keyPrefix;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  /// The duration typed, or null when a field is not a whole number or the
  /// total is under a minute.
  ///
  /// Accepts every digit set, and an empty field reads as zero.
  static Duration? read(
      TextEditingController hours, TextEditingController minutes) {
    int? field(TextEditingController controller) {
      final text = Digits.toLatin(controller.text.trim());
      return text.isEmpty ? 0 : int.tryParse(text);
    }

    final h = field(hours);
    final m = field(minutes);
    if (h == null || m == null || h < 0 || m < 0) return null;
    final duration = Duration(hours: h, minutes: m);
    return duration.inMinutes < 1 ? null : duration;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    InputDecoration decoration(String label, {String? error}) =>
        InputDecoration(
          labelText: label,
          errorText: error,
          border: const OutlineInputBorder(),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: Key('$keyPrefix-hours'),
            controller: hours,
            keyboardType: TextInputType.number,
            decoration: decoration(l10n.trackerHoursLabel, error: errorText),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: NimbusTokens.space4),
        Expanded(
          child: TextField(
            key: Key('$keyPrefix-minutes'),
            controller: minutes,
            keyboardType: TextInputType.number,
            decoration: decoration(l10n.trackerMinutesLabel),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
