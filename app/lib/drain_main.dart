import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bootstrap/database_provider.dart';
import 'bootstrap/provider_retry.dart';
import 'features/notifications/application/outside_errors.dart';
import 'features/notifications/data/outside_channel.dart';
import 'features/widget/application/drain_service.dart';

/// The widget drain's headless engine (spec §2.4). DrainJobService starts it
/// when no app engine is alive.
///
/// It opens the database exactly as `main()` does, drains, checks every
/// goal, and tells native it is done. There is no widget tree and no
/// `runApp`. The widget tap itself never comes here: it ended with a buffer
/// append.
@pragma('vm:entry-point')
Future<void> drainMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = OutsideChannel();
  AppDatabase? db;
  ProviderContainer? container;
  var ok = false;
  try {
    final dir = await getApplicationDocumentsDirectory();
    db = AppDatabase.openAtPath(p.join(dir.path, 'nimbustats.sqlite'));
    container = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(channel),
    ]);
    ok = await runDrain(container);
  } on Object catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'widget drain',
      context: ErrorDescription('while draining in the headless engine'),
    ));
  } finally {
    container?.dispose();
    await db?.close();
    await reportingFailure('widget drain', 'while telling native the drain ended',
        () => channel.drainFinished(ok));
  }
}

/// One drain in [container]: what both engines run (spec §2.4). The channel
/// is the container's own `outsideChannelProvider`.
Future<bool> runDrain(ProviderContainer container) =>
    container.read(drainServiceProvider).run();
