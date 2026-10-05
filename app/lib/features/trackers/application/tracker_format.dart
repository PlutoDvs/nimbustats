import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// How tracker numbers read: digits, separators, units, times and dates.
///
/// Digits follow the settings locale, like every other number in the app
/// (screen contract §8). Amounts go through `NumberFormat.decimalPattern` for
/// that locale, and times and durations through [Digits]. Every string that
/// shows a tracker number gets it from here, as a ready string, so the ARB
/// strings never format a number themselves.
final class TrackerFormat {
  TrackerFormat({
    required String localeTag,
    required this.persianDigits,
    required this.calendar,
  }) : _number = NumberFormat.decimalPattern(localeTag)
          ..maximumFractionDigits = 2;

  final bool persianDigits;
  final AppCalendar calendar;
  final NumberFormat _number;

  /// A count or an amount: `2.5`, `۲٫۵`, `1,250`. Two decimals at most, so a
  /// float sum like 0.1 + 0.2 reads as 0.3.
  String number(double value) => _number.format(value);

  /// A whole number in the settings' digits, without grouping: a day count, a
  /// day of the month, an hour, a year. [number] would write 1405 as `1,405`.
  String digits(int value) => _digits('$value');

  /// A tracker's total as its type shows it: a count, an amount with its unit,
  /// or a time as h:mm.
  ///
  /// A boolean's total is the times done, which the screens put into words
  /// instead.
  String total(Tracker tracker, double total) => switch (tracker.type) {
        TrackerType.counter || TrackerType.boolean => number(total),
        TrackerType.quantity => tracker.unit == null
            ? number(total)
            : '${number(total)} ${tracker.unit}',
        TrackerType.duration => duration(TrackerValues.durationOf(total)),
      };

  /// h:mm, for totals: `1:30`, `0:12`.
  String duration(Duration value) =>
      _digits('${value.inHours}:${_two(value.inMinutes % 60)}');

  /// h:mm:ss, for a running timer, which ticks.
  String elapsed(Duration value) => _digits('${value.inHours}:'
      '${_two(value.inMinutes % 60)}:${_two(value.inSeconds % 60)}');

  /// A wall-clock time, 24-hour: `07:05`.
  String time(DateTime local) =>
      _digits('${_two(local.hour)}:${_two(local.minute)}');

  /// A date in the active calendar, written as the transaction list writes
  /// one.
  String date(DateKey day) {
    final parts = calendar.partsOf(day);
    return _digits('${parts.year}/${_two(parts.month)}/${_two(parts.day)}');
  }

  String _digits(String latin) =>
      persianDigits ? Digits.toPersian(latin) : latin;

  static String _two(int value) => value.toString().padLeft(2, '0');
}

final trackerFormatProvider = Provider<TrackerFormat>((ref) => TrackerFormat(
      localeTag: ref.watch(localeProvider).languageCode,
      persianDigits: ref.watch(moneyFormatterProvider).persianDigits,
      calendar: ref.watch(calendarProvider),
    ));
