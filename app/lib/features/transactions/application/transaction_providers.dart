import 'package:flutter_riverpod/flutter_riverpod.dart';

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
