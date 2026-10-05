import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_clock.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

/// A clock the test moves by hand.
///
/// Starts at 2026-10-05 09:00 UTC, which is 12:30 in Tehran, the default zone
/// here, so "today" is 20261005.
final class FakeClock {
  FakeClock({DateTime? nowUtc, this.offset = tehran})
      : nowUtc = nowUtc ?? DateTime.utc(2026, 10, 5, 9);

  static const tehran = Duration(hours: 3, minutes: 30);
  static const newYork = Duration(hours: -4);

  DateTime nowUtc;

  /// The device's UTC offset. Change it to fly.
  Duration offset;

  void advance(Duration by) => nowUtc = nowUtc.add(by);

  /// Reads this fake's fields on every call, so moving the fake also moves a
  /// clock already handed to a repository or a provider.
  TrackerClock get clock => TrackerClock(
        nowUtc: () => nowUtc,
        toLocal: (utc) => utc.add(offset),
        fromLocal: (wall) => DateTime.utc(wall.year, wall.month, wall.day,
                wall.hour, wall.minute, wall.second)
            .subtract(offset),
      );
}

const cigarettes = TrackerDraft(
    name: 'Cigarettes',
    iconKey: 'smoking_rooms',
    color: 0xFF546E7A,
    type: TrackerType.counter);
const gym = TrackerDraft(
    name: 'Gym',
    iconKey: 'fitness_center',
    color: 0xFF2E7D32,
    type: TrackerType.boolean);
const water = TrackerDraft(
    name: 'Water',
    iconKey: 'water_drop',
    color: 0xFF1565C0,
    type: TrackerType.quantity,
    unit: 'L',
    perTapValue: 0.25);
const sleep = TrackerDraft(
    name: 'Sleep',
    iconKey: 'bedtime',
    color: 0xFF4527A0,
    type: TrackerType.duration);

TrackerRepository repositoryFor(AppDatabase db, FakeClock fake) =>
    TrackerRepository(db.trackersDao, db.trackerEntriesDao, fake.clock);
