import '../money/digits.dart';
import 'tracker_type.dart';

/// What an entry's value means under each [TrackerType], in one place.
///
/// | type     | one entry's value          | a day's total         |
/// |----------|----------------------------|-----------------------|
/// | counter  | 1                          | the sum, a count      |
/// | boolean  | 1, at most one live a day  | done when above zero  |
/// | quantity | the amount                 | the sum               |
/// | duration | whole seconds              | the sum               |
abstract final class TrackerValues {
  /// What one tap logs, or null for a duration tracker: a tap on one starts or
  /// stops its timer instead.
  ///
  /// Throws [ArgumentError] for a quantity tracker without a per-tap amount.
  /// The repository refuses to create one, so meeting one here is a bug, and
  /// logging a guessed amount would hide it.
  static double? perTap(TrackerType type, {double? perTapValue}) =>
      switch (type) {
        TrackerType.counter || TrackerType.boolean => 1.0,
        TrackerType.quantity => perTapValue ??
            (throw ArgumentError.value(perTapValue, 'perTapValue',
                'a quantity tracker logs its per-tap amount')),
        TrackerType.duration => null,
      };

  /// Whether [value] may be stored as one entry of a [type] tracker.
  static bool isValid(TrackerType type, double value) => switch (type) {
        TrackerType.counter || TrackerType.boolean => value == 1.0,
        TrackerType.quantity => value.isFinite && value > 0,
        TrackerType.duration =>
          value.isFinite && value >= 1 && value == value.roundToDouble(),
      };

  /// A boolean tracker's day total, read as done.
  static bool isDone(double total) => total > 0;

  /// A duration entry's value: whole seconds, rounded down, so a timer stopped
  /// at 59.9 seconds logs 59 -- never a second it did not run.
  static double secondsOf(Duration duration) =>
      duration.inSeconds.toDouble();

  /// A duration entry's value read back as a [Duration].
  static Duration durationOf(double seconds) =>
      Duration(seconds: seconds.round());

  /// Checks a tracker's definition before it is stored.
  ///
  /// A quantity tracker needs a valid per-tap amount, and its unit is
  /// optional. Every other type has neither. Throws [ArgumentError] otherwise:
  /// the editor validates for the user, so a bad definition reaching here is a
  /// caller's bug.
  static void checkDefinition(
    TrackerType type, {
    String? unit,
    double? perTapValue,
  }) {
    if (type == TrackerType.quantity) {
      if (perTapValue == null || !isValid(TrackerType.quantity, perTapValue)) {
        throw ArgumentError.value(perTapValue, 'perTapValue',
            'a quantity tracker needs a per-tap amount above zero');
      }
      return;
    }
    if (unit != null) {
      throw ArgumentError.value(
          unit, 'unit', 'only a quantity tracker has a unit');
    }
    if (perTapValue != null) {
      throw ArgumentError.value(perTapValue, 'perTapValue',
          'only a quantity tracker has a per-tap amount');
    }
  }

  static final _decimal = RegExp(r'^(\d+(\.\d*)?|\.\d+)$');

  /// Reads an amount the user typed, or null unless it is a finite number
  /// above zero.
  ///
  /// Accepts:
  /// - Latin, Persian and Arabic-Indic digits;
  /// - `.`, the Arabic decimal separator `٫` (U+066B) or `/` for the decimal
  ///   point (`/` is how many Persian speakers type one);
  /// - `,` and `٬` (U+066C) as grouping, which is dropped.
  ///
  /// Matched against a strict pattern before parsing, because `double.parse`
  /// alone would accept `1e3`, `NaN` and `Infinity`.
  static double? parseAmount(String input) {
    final normalised = Digits.toLatin(input.trim())
        .replaceAll('٫', '.')
        .replaceAll('/', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '');
    if (!_decimal.hasMatch(normalised)) return null;
    final value = double.parse(normalised);
    return value.isFinite && value > 0 ? value : null;
  }
}
