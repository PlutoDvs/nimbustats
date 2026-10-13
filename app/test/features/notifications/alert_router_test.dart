import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/goals/application/goal_watcher.dart';
import 'package:nimbustats/features/notifications/application/alert_router.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/fake_outside_channel.dart';

/// The router as both engines run it: real providers over a test database,
/// with the channel faked and the lifecycle injected.
void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late FakeOutsideChannel outside;
  late bool foreground;

  const day5 = DateKey(20261005);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    outside = FakeOutsideChannel();
    foreground = false;
    await seedCategories(db);
    await useEnglishDigits(db); // English settings: English notification text
    await service.save(spendingCap()); // 'Dining out', 1,000,000 a month
    await spend(db, 850000, day5); // 85%: crosses 80
  });
  tearDown(() => db.close());

  late List<GoalAlert> snackbars;

  Future<(AlertRouter, GoalWatcher)> start() async {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ...trackerOverrides(fake),
      outsideChannelProvider.overrideWithValue(outside),
      isForegroundProvider.overrideWithValue(() => foreground),
    ]);
    addTearDown(c.dispose);
    final router = c.read(alertRouterProvider);
    snackbars = [];
    final subscription = router.foregroundAlerts.listen(snackbars.add);
    addTearDown(subscription.cancel);
    return (router, c.read(goalWatcherProvider));
  }

  Future<void> cross(AlertRouter router, GoalWatcher watcher) async {
    await watcher.checkNow();
    await Future<void>.delayed(Duration.zero); // the broadcast delivery
    await router.idle();
  }

  test('in the foreground an alert goes to the snackbar stream only',
      () async {
    foreground = true;
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(snackbars.single.percent, 80);
    expect(outside.posted, isEmpty);
  });

  test('otherwise it posts one discreet notification, tagged per goal, that '
      'opens the goal', () async {
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(snackbars, isEmpty);
    expect(outside.posted, [
      (
        tag: 'goal:cap',
        text: 'A goal needs a look',
        publicText: 'A goal needs a look',
        route: '/goals/cap',
      ),
    ]);
  });

  test('with details on, the text is the full alert; the lock screen still '
      'gets the discreet one', () async {
    await NotificationPrefsRepository(db.settingsDao).setShowDetails(true);
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(outside.posted.single.text, "Dining out: 85% of this month's limit");
    expect(outside.posted.single.publicText, 'A goal needs a look');
  });

  test('recomputation posts nothing more', () async {
    final (router, watcher) = await start();
    await cross(router, watcher);
    await cross(router, watcher);
    expect(outside.posted, hasLength(1));
  });

  test('a failed post is reported under "alert router", not retried',
      () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    outside.postError = PlatformException(code: 'boom');

    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(reported.single.library, 'alert router');
    expect(outside.calls.where((c) => c == 'postAlert'), hasLength(1));
  });

  test('a corrupt app setting still posts the alert, with no second report',
      () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    // The settings screen surfaces this one; it must not cost an alert.
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');

    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(outside.posted.single.tag, 'goal:cap');
    expect(reported, isEmpty);
  });
}
