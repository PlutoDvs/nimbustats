import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/widget/application/snapshot_writer.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository trackers;

  const day5 = DateKey(20261005);

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock(); // 2026-10-05, 12:30 in Tehran
    trackers = repositoryFor(db, fake);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> snapshot() async =>
      jsonDecode(await SnapshotWriter(db, fake.clock).build())
          as Map<String, Object?>;

  List<Map<String, Object?>> rows(Map<String, Object?> s, String key) =>
      (s[key]! as List<Object?>).cast<Map<String, Object?>>();

  test('trackers: tab order, no duration, none archived, at most four, with '
      "today's totals", () async {
    final cig = await trackers.create(cigarettes);
    final gymTracker = await trackers.create(gym);
    final waterTracker = await trackers.create(water);
    await trackers.create(sleep); // duration: a timer cannot run from a widget
    final old = await trackers.create(const TrackerDraft(
        name: 'Old', iconKey: 'tag', color: 1, type: TrackerType.counter));
    await trackers.archive(old.id);
    final coffee = await trackers.create(const TrackerDraft(
        name: 'Coffee', iconKey: 'tag', color: 2, type: TrackerType.counter));
    await trackers.create(const TrackerDraft(
        name: 'Tea', iconKey: 'tag', color: 3, type: TrackerType.counter));

    for (var i = 0; i < 3; i++) {
      await trackers.logEntry(cig.id);
    }
    await trackers.logEntry(cig.id,
        at: DateTime.utc(2026, 10, 4, 12)); // yesterday: not today's
    await trackers.logEntry(gymTracker.id);
    await trackers.logEntry(waterTracker.id);
    await trackers.logEntry(waterTracker.id);

    final s = await snapshot();
    expect([for (final t in rows(s, 'trackers')) t['name']],
        ['Cigarettes', 'Gym', 'Water', 'Coffee']);
    final byName = {for (final t in rows(s, 'trackers')) t['name']: t};
    expect(byName['Cigarettes'], {
      'id': cig.id,
      'name': 'Cigarettes',
      'color': 0xFF546E7A,
      'type': 'counter',
      'perTap': 1.0,
      'unit': null,
      'todayTotal': 3.0,
    });
    expect(byName['Gym']!['todayTotal'], 1.0);
    expect(byName['Water']!['perTap'], 0.25);
    expect(byName['Water']!['unit'], 'L');
    expect(byName['Water']!['todayTotal'], 0.5);
    expect(byName['Coffee']!['id'], coffee.id);
    expect(byName['Coffee']!['todayTotal'], 0.0);
  });

  test('chips: up to four predicted categories, never Uncategorized',
      () async {
    await spend(db, 1000, day5); // Dining
    await spend(db, 1000, day5, category: 'seed-transport');

    final chips = rows(await snapshot(), 'chips');
    expect(chips.length, lessThanOrEqualTo(4));
    expect(chips, contains(equals({'id': 'seed-dining', 'name': 'Dining'})));
    expect(chips.map((c) => c['id']),
        isNot(contains(SystemCategoryIds.uncategorized)));
  });

  test('the day, the language, the direction and the currency', () async {
    final s = await snapshot();
    expect(s['v'], 1);
    expect(s['dayKey'], 20261005);
    expect(s['localeTag'], 'fa'); // the settings default
    expect(s['rtl'], isTrue);
    expect(s['currency'], {
      'code': 'IRT',
      'decimalDigits': 0,
      'label': 'تومان',
    });
    expect(rows(s, 'trackers'), isEmpty);

    await useEnglishDigits(db); // settings locale: en
    final en = await snapshot();
    expect(en['localeTag'], 'en');
    expect(en['rtl'], isFalse);
    expect((en['currency']! as Map)['label'], 'Toman');
  });

  test('strings are in the app language, templates keep their slots',
      () async {
    final fa = (await snapshot())['strings']! as Map<String, Object?>;
    expect(fa['trackerAdd'], '{name}، امروز {total}. افزودن یکی');
    expect(fa['trackerDone'], '{name}، امروز انجام شد');

    await useEnglishDigits(db);
    final en = (await snapshot())['strings']! as Map<String, Object?>;
    expect(en, {
      'addExpense': '+ Expense',
      'emptyTrackers': 'Add a tracker in the app to log it from here',
      'entryTitle': 'Add expense',
      'save': 'Save',
      'cancel': 'Cancel',
      'saved': 'Saved',
      'trackerAdd': '{name}, today {total}. Add one',
      'trackerDone': '{name}, done today',
    });
  });

  test('a corrupt setting builds with the defaults, as every screen does',
      () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    final s = await snapshot();
    expect(s['localeTag'], 'fa');
    expect((s['currency']! as Map)['code'], 'IRT');
  });
}
