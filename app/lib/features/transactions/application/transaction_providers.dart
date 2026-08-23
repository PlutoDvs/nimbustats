import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../../settings/application/settings_providers.dart';
import '../data/transaction_repository.dart';

/// The app's only transaction write path.
///
/// Watches [currencyProvider] rather than reading it once, so a transaction
/// recorded after the user changes currency is stamped with the new one -- and
/// rows written earlier keep the code they were written with.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TransactionRepository(
    db.transactionsDao,
    db.tagsDao,
    ref.watch(currencyProvider),
  );
});

/// One transaction, for the detail screen.
///
/// A family rather than a single provider, so opening two details in a row
/// does not make the second wait on the first being disposed.
final transactionByIdProvider =
    FutureProvider.family<Transaction?, String>((ref, id) async =>
        ref.watch(appDatabaseProvider).transactionsDao.byId(id));

/// The tag ids attached to one transaction.
final transactionTagsProvider =
    FutureProvider.family<List<String>, String>((ref, id) =>
        ref.watch(transactionRepositoryProvider).tagsOf(id));
