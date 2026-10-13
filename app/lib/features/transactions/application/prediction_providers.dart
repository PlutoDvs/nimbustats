import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';

/// How much history the predictor is built from.
///
/// Enough for the ranking to be stable -- a handful of rows would let one
/// unusual afternoon dominate the chips -- and small enough to load on every
/// open of the add screen without anyone noticing. It is three fields per row,
/// not whole transactions, so this is a few tens of kilobytes at worst.
const predictionHistoryLimit = 300;

/// The predictor built from [db]'s recent history, read once. Shared by the
/// add screen's provider and Phase 6's widget snapshot, so both rank the
/// same chips.
Future<CategoryPredictor> loadCategoryPredictor(AppDatabase db) async {
  final usage = await db.transactionsDao.recentCategoryUsage(
    limit: predictionHistoryLimit,
  );
  return MruFrequencyCategoryPredictor([
    for (final row in usage)
      CategoryObservation(
        categoryId: row.categoryId,
        occurredAt: row.occurredAt.toLocal(),
        merchant: row.merchant,
      ),
  ]);
}

/// The category predictor for the add screen.
///
/// Typed as the interface, not the implementation, so Phase 2 can swap in
/// merchant-rule-backed prediction by changing this provider and nothing else.
final categoryPredictorProvider = FutureProvider<CategoryPredictor>(
  (ref) => loadCategoryPredictor(ref.watch(appDatabaseProvider)),
);
