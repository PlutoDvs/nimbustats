import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Cheap Argon2id settings (ruling R10). The header carries them, so every
/// other step is the production path.
const fastKdf = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

/// A file-backed WAL database and its [BackupService], in a temp dir of its
/// own: what the app has, minus the platform paths.
final class BackupFixture {
  BackupFixture._(this.dir, this.db, this.service);

  factory BackupFixture.open({
    DateTime Function()? clock,
    Duration busyTimeout = const Duration(seconds: 5),
  }) {
    final dir = Directory.systemTemp.createTempSync('nimbus_backup');
    String at(String name) => '${dir.path}${Platform.pathSeparator}$name';
    final db = AppDatabase.openAtPath(at('nimbustats.sqlite'));
    return BackupFixture._(
      dir,
      db,
      BackupService(
        db: db,
        livePath: at('nimbustats.sqlite'),
        cacheDir: at('cache'),
        preRestorePath: at('nimbustats.pre-restore.sqlite'),
        kdf: fastKdf,
        clock: clock ?? DateTime.now,
        busyTimeout: busyTimeout,
      ),
    );
  }

  final Directory dir;
  final AppDatabase db;
  final BackupService service;

  String get livePath => path('nimbustats.sqlite');

  String get preRestorePath => path('nimbustats.pre-restore.sqlite');

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  /// The names in the service's cache directory, folders included.
  List<String> cacheFiles() {
    final cache = Directory(service.cacheDir);
    if (!cache.existsSync()) return [];
    return [
      for (final entry in cache.listSync())
        entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
    ];
  }

  /// One expense under a category of its own, committed and never
  /// checkpointed: the connection stays open, so the row lives in the WAL.
  Future<String> addExpense({
    int amount = 12345,
    DateTime? occurredAtUtc,
    DateKey? on,
  }) async {
    final id = 'tx-$amount';
    await db.categoriesDao
        .insertNode(id: 'cat-$amount', name: 'Category $amount', parentId: null);
    await db.transactionsDao.insertTransaction(
      id: id,
      direction: TxDirection.expense,
      amount: Money(amount),
      currencyCode: 'IRT',
      occurredAtUtc: (occurredAtUtc ?? DateTime.utc(2026, 10, 17, 9))
          .millisecondsSinceEpoch,
      localDateKey: on ?? DateKey.fromParts(2026, 10, 17),
      categoryId: 'cat-$amount',
      source: TxSource.manual,
      isConfirmed: true,
    );
    return id;
  }

  Future<void> close() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}
