import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'bootstrap/database_provider.dart';

/// Bootstrap only.
///
/// The app layer owns *where* the database file lives, because it is the only
/// layer allowed to know the platform's directory conventions and the only one
/// with `path_provider`. `nimbus_data` receives the path and decides how to
/// open it. Everything else the app needs is resolved through providers, so
/// this function stays short enough to be obviously correct.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  final db = AppDatabase.openAtPath(p.join(dir.path, 'nimbustats.sqlite'));

  runApp(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const NimbuStatsApp(),
  ));
}
