import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/category_repository.dart';
import '../data/category_tree.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(appDatabaseProvider).categoriesDao),
);

/// The nested category tree, re-emitted on every write.
///
/// Kept alive for the same reason as the settings stream: the picker on the
/// add-expense screen reads this on every open, and letting the SQLite
/// subscription tear down and rebuild between screens is churn with no
/// benefit.
final categoryTreeProvider = StreamProvider<List<CategoryNode>>((ref) {
  ref.keepAlive();
  return ref.watch(categoryRepositoryProvider).watchTree();
});
