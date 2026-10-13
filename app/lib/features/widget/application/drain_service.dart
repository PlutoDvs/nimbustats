import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../../goals/application/goal_watcher.dart';
import '../../notifications/application/alert_router.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/data/settings_repository.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../trackers/data/tracker_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import 'snapshot_writer.dart';
import 'widget_drain.dart';

/// One drain of the widget buffer, in whichever engine runs it (spec §2.3):
/// 1. take every pending line;
/// 2. write each through the repositories;
/// 3. build a fresh snapshot;
/// 4. commit the snapshot, the acks and the rejects in one native call;
/// 5. report every rejection;
/// 6. check every goal, and wait for any notification to post.
///
/// Drains and snapshot writes in one engine are queued, never run side by
/// side. So a snapshot built from rows a drain has written never meets the
/// lines that drain is about to ack.
final class DrainService {
  DrainService(this._ref);

  final Ref _ref;
  Future<void> _tail = Future.value();

  /// Returns whether every line was settled (ruling R10).
  Future<bool> run() => _queued(_drain);

  /// The app engine's snapshot rewrite (`WidgetSync`), queued like a drain.
  Future<void> refreshSnapshot() => _queued(() async => _ref
      .read(outsideChannelProvider)
      .writeSnapshot(await _ref.read(snapshotWriterProvider).build()));

  Future<T> _queued<T>(Future<T> Function() job) {
    final result = _tail.then((_) => job());
    // The caller gets the failure through [result]. The queue itself only
    // waits for the job to end.
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _drain() async {
    final channel = _ref.read(outsideChannelProvider);
    // Subscribed before the goal check can emit.
    final alerts = _ref.read(alertRouterProvider);
    final lines = await channel.takeBuffer();
    if (lines.isEmpty) return true;

    final db = _ref.read(appDatabaseProvider);
    // Read once, not from the settings stream. A headless engine drains
    // before that stream emits, and would stamp the default currency.
    final settings = await SettingsRepository(db.settingsDao).load();
    final outcome = await WidgetDrain(
      db: db,
      transactions: TransactionRepository(
          db.transactionsDao, db.tagsDao, settings.currency),
      trackers: TrackerRepository(
        db.trackersDao,
        db.trackerEntriesDao,
        AnalyticsEngine(db, calendar: settings.calendar),
        _ref.read(trackerClockProvider),
      ),
    ).apply(lines);

    await channel.commitDrain(
      snapshot: await _ref.read(snapshotWriterProvider).build(),
      ackIds: outcome.ackIds,
      rejected: outcome.rejected,
    );
    for (final rejected in outcome.rejected) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('widget buffer line rejected: ${rejected.reason}'),
        library: 'widget drain',
        context: ErrorDescription(
            'kept in widget_buffer.rejected.jsonl: ${rejected.line}'),
      ));
    }

    await _ref.read(goalWatcherProvider).checkNow();
    // The alerts stream delivers in a microtask; then the posts it started.
    await Future<void>.delayed(Duration.zero);
    await alerts.idle();
    return outcome.failed == 0;
  }
}

final drainServiceProvider = Provider<DrainService>(DrainService.new);
