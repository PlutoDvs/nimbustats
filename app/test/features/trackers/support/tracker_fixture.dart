import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
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

/// What a tracker widget test overrides: the clock, so "today" and the timer
/// are the fake's.
List<Override> trackerOverrides(FakeClock fake) =>
    [trackerClockProvider.overrideWithValue(fake.clock)];

/// Saves English as the settings locale, so numbers render in Latin digits.
///
/// Without it they are Persian whatever locale the test pumps: digits follow
/// the settings locale, whose default is fa.
Future<void> useEnglishDigits(AppDatabase db) =>
    SettingsRepository(db.settingsDao)
        .save(AppSettings.defaults.copyWith(locale: const Locale('en')));

/// The text shown under a keyed widget.
String textIn(WidgetTester tester, Key key) => tester
    .widget<Text>(find
        .descendant(of: find.byKey(key), matching: find.byType(Text))
        .first)
    .data!;

/// Sends the app to the background and back, one lifecycle step at a time,
/// as Android does. AppLifecycleListener asserts each step is a legal one.
Future<void> backgroundAndResume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}

/// Reads a stream's current value from a widget test's body.
///
/// A drift stream delivers its first value from a timer, and a widget test's
/// timers only fire while the test pumps. Awaiting `.first` straight from the
/// test body therefore waits forever; this reads it on the real clock.
Future<T> firstOf<T>(WidgetTester tester, Stream<T> stream) async =>
    (await tester.runAsync(() => stream.first)) as T;

/// Records every haptic the app asks for, as the platform channel sees it:
/// `HapticFeedbackType.lightImpact` and so on, or `vibrate` for
/// `HapticFeedback.vibrate()`, which sends no argument.
List<String> captureHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments?.toString() ?? 'vibrate');
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return haptics;
}

/// Taps [finder] after scrolling it into view.
///
/// The editor sheets scroll: with the shared icon grid they are taller than
/// an 800 x 600 test screen, and a user scrolls to Save the same way.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // Dismiss the keyboard first, as a user does. A focused field keeps its
  // caret on screen and would scroll the sheet back up after ensureVisible.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
