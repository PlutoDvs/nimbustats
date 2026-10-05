import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('perTap', () {
    test('a counter and a boolean log exactly one', () {
      expect(TrackerValues.perTap(TrackerType.counter), 1.0);
      expect(TrackerValues.perTap(TrackerType.boolean), 1.0);
    });

    test('a quantity logs its per-tap amount', () {
      expect(
          TrackerValues.perTap(TrackerType.quantity, perTapValue: 0.25), 0.25);
    });

    test('a quantity without a per-tap amount is a bug, not a zero', () {
      expect(() => TrackerValues.perTap(TrackerType.quantity),
          throwsArgumentError);
    });

    test('a duration tap logs nothing: it starts or stops the timer', () {
      expect(TrackerValues.perTap(TrackerType.duration), isNull);
    });
  });

  group('isValid', () {
    test('counter and boolean entries are exactly one', () {
      for (final type in [TrackerType.counter, TrackerType.boolean]) {
        expect(TrackerValues.isValid(type, 1), isTrue, reason: '$type');
        expect(TrackerValues.isValid(type, 2), isFalse, reason: '$type');
        expect(TrackerValues.isValid(type, 0), isFalse, reason: '$type');
      }
    });

    test('a quantity is any finite amount above zero', () {
      expect(TrackerValues.isValid(TrackerType.quantity, 2.5), isTrue);
      expect(TrackerValues.isValid(TrackerType.quantity, 0), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, -1), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, double.nan), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, double.infinity),
          isFalse);
    });

    test('a duration is whole seconds, at least one', () {
      expect(TrackerValues.isValid(TrackerType.duration, 5400), isTrue);
      expect(TrackerValues.isValid(TrackerType.duration, 1), isTrue);
      expect(TrackerValues.isValid(TrackerType.duration, 0), isFalse);
      expect(TrackerValues.isValid(TrackerType.duration, 1.5), isFalse);
    });
  });

  test('a boolean total above zero reads as done', () {
    expect(TrackerValues.isDone(1), isTrue);
    expect(TrackerValues.isDone(0), isFalse);
  });

  group('durations', () {
    test('an entry holds whole seconds, rounded down', () {
      // A timer stopped at 59.9 seconds logs 59, never a second it did not
      // run.
      expect(
          TrackerValues.secondsOf(
              const Duration(seconds: 59, milliseconds: 900)),
          59.0);
    });

    test('a stored value reads back as a duration', () {
      expect(TrackerValues.durationOf(5400),
          const Duration(hours: 1, minutes: 30));
    });
  });

  group('checkDefinition', () {
    test('a quantity needs a positive per-tap amount; its unit is optional',
        () {
      TrackerValues.checkDefinition(TrackerType.quantity, perTapValue: 0.25);
      TrackerValues.checkDefinition(TrackerType.quantity,
          unit: 'L', perTapValue: 0.25);
      expect(() => TrackerValues.checkDefinition(TrackerType.quantity),
          throwsArgumentError);
      expect(
          () => TrackerValues.checkDefinition(TrackerType.quantity,
              perTapValue: 0),
          throwsArgumentError);
    });

    test('only a quantity has a unit or a per-tap amount', () {
      for (final type in [
        TrackerType.counter,
        TrackerType.boolean,
        TrackerType.duration,
      ]) {
        TrackerValues.checkDefinition(type);
        expect(() => TrackerValues.checkDefinition(type, unit: 'L'),
            throwsArgumentError,
            reason: '$type');
        expect(() => TrackerValues.checkDefinition(type, perTapValue: 1),
            throwsArgumentError,
            reason: '$type');
      }
    });
  });

  group('parseAmount', () {
    // Persian keyboards, the Arabic-Indic set and copy-paste all reach this
    // field. Refusing them would turn a correct amount into a "wrong amount"
    // error the user cannot fix.
    const accepted = {
      '2.5': 2.5,
      '۲٫۵': 2.5,
      '۲/۵': 2.5,
      '٢٫٥': 2.5,
      '1,250': 1250.0,
      '۱٬۲۵۰': 1250.0,
      ' 3 ': 3.0,
      '.5': 0.5,
      '2.': 2.0,
    };
    accepted.forEach((input, value) {
      test('reads "$input" as $value', () {
        expect(TrackerValues.parseAmount(input), value);
      });
    });

    for (final input in [
      '',
      '0',
      '0.0',
      '-1',
      'abc',
      '1e3',
      'NaN',
      'Infinity',
      '2.5.1',
      '.',
    ]) {
      test('refuses "$input"', () {
        expect(TrackerValues.parseAmount(input), isNull);
      });
    }
  });
}
