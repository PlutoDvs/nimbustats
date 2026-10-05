import 'package:nimbus_domain/nimbus_domain.dart';

/// The wall clock the trackers feature reads, injectable so a test can stand
/// at any instant and in any timezone.
///
/// Two questions, kept apart on purpose:
/// - *When* something happens is an instant ([nowUtc]).
/// - *Which day* it belongs to depends on where the device is when it is
///   written ([toLocal]).
/// A flight between two entries changes the second answer and not the first.
final class TrackerClock {
  const TrackerClock({
    this._nowUtc = _systemNowUtc,
    this._toLocal = _systemToLocal,
    this._fromLocal = _systemFromLocal,
  });

  final DateTime Function() _nowUtc;
  final DateTime Function(DateTime utc) _toLocal;
  final DateTime Function(DateTime wall) _fromLocal;

  DateTime nowUtc() => _nowUtc().toUtc();

  /// The wall-clock time [utc] reads as, in the device's timezone right now.
  DateTime toLocal(DateTime utc) => _toLocal(utc.toUtc());

  /// The instant a wall-clock time picked on this device means. Only [wall]'s
  /// date and time fields are read.
  DateTime fromLocal(DateTime wall) => _fromLocal(wall).toUtc();

  /// The local date [utc] falls on, here and now.
  DateKey localDateOf(DateTime utc) => DateKey.fromDateTime(toLocal(utc));

  DateKey today() => localDateOf(nowUtc());

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  static DateTime _systemToLocal(DateTime utc) => utc.toLocal();

  static DateTime _systemFromLocal(DateTime wall) => DateTime(wall.year,
          wall.month, wall.day, wall.hour, wall.minute, wall.second)
      .toUtc();
}
