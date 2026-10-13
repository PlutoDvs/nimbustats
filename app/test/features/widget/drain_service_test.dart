import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/drain_main.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

import '../goals/support/goal_test_app.dart';
import '../notifications/support/fake_outside_channel.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/buffer_lines.dart';

/// One drain as the headless engine runs it: a bare container, no widget
/// tree, the channel faked (spec §10, "runDrain end to end").
void main() {
  late AppDatabase db;
  late FakeClock fake;
  late FakeOutsideChannel outside;

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    outside = FakeOutsideChannel();
    await seedCategories(db);
  });
  tearDown(() => db.close());

  ProviderContainer engine() {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(outside),
      ...trackerOverrides(fake),
      // The headless engine has no lifecycle.
      isForegroundProvider.overrideWithValue(() => false),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('takes, writes, commits once with a fresh snapshot; the buffer '
      'empties', () async {
    outside.buffer = [expense('e1'), 'garbage'];
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    expect(await runDrain(engine()), isTrue);

    expect(outside.commits, hasLength(1));
    expect(outside.commits.single.ackIds, ['e1']);
    expect(outside.commits.single.rejected.single.line, 'garbage');
    expect(jsonDecode(outside.commits.single.snapshot), containsPair('v', 1));
    expect(outside.buffer, isEmpty);
    expect(reported.single.library, 'widget drain',
        reason: 'every rejection is reported');
  });

  test('a fresh engine stamps the saved currency, not the default', () async {
    await SettingsRepository(db.settingsDao)
        .save(AppSettings.defaults.copyWith(currency: Currency.usd));
    outside.buffer = [expense('e2', amount: 1250)];

    await runDrain(engine());

    final tx = (await db.transactionsDao.byId('e2'))!;
    expect(tx.currencyCode, 'USD');
    expect(tx.amount, const Money(1250));
  });

  test('a crossing the drain causes is posted before the drain ends',
      () async {
    final service = goalServiceFor(db, fake.clock.today);
    await service.save(spendingCap()); // 1,000,000 a month on Dining
    outside.buffer = [expense('e3', amount: 850000, category: 'seed-dining')];

    await runDrain(engine());

    expect(outside.posted.single.tag, 'goal:cap');
    expect(outside.calls.indexOf('commitDrain'),
        lessThan(outside.calls.indexOf('postAlert')));
  });

  test('a line that failed unexpectedly makes the drain not ok', () async {
    final bare = AppDatabase.openInMemory();
    addTearDown(bare.close);
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previous);
    outside.buffer = [expense('e4')];
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(bare), // no categories: FK fails
      outsideChannelProvider.overrideWithValue(outside),
      isForegroundProvider.overrideWithValue(() => false),
    ]);
    addTearDown(c.dispose);

    expect(await runDrain(c), isFalse);
    expect(outside.buffer, [expense('e4')], reason: 'kept for the next drain');
  });

  test('an empty buffer commits nothing', () async {
    expect(await runDrain(engine()), isTrue);
    expect(outside.commits, isEmpty);
  });
}
