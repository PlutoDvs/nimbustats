import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';

/// How much history the predictor is built from.
///
/// Enough for the ranking to be stable -- a handful of rows would let one
/// unusual afternoon dominate the chips -- and small enough to load on every
/// open of the add screen without anyone noticing. It is three fields per row,
/// not whole transactions, so this is a few tens of kilobytes at worst.
const predictionHistoryLimit = 300;

/// The category predictor for the add screen.
///
/// Typed as the interface, not the implementation, so Phase 2 can swap in
/// merchant-rule-backed prediction by changing this provider and nothing else.
final categoryPredictorProvider = FutureProvider<CategoryPredictor>((ref) async {
  final usage = await ref
      .watch(appDatabaseProvider)
      .transactionsDao
      .recentCategoryUsage(limit: predictionHistoryLimit);

  return MruFrequencyCategoryPredictor([
    for (final row in usage)
      CategoryObservation(
        categoryId: row.categoryId,
        occurredAt: row.occurredAt.toLocal(),
        merchant: row.merchant,
      ),
  ]);
});
