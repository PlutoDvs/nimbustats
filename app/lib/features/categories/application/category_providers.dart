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

/// Every category by id, for turning an id a query returned back into a name.
///
/// Built from [categoryTreeProvider], which includes archived rows. That is
/// the point: archived is a *picker* concern, and dropping those here would
/// silently shrink last month's spending the moment somebody tidied their
/// tree. The nodes are kept whole rather than reduced to names so a caller can
/// also ask whether a category has children -- which is what tells a
/// breakdown row whether it can be drilled into.
final categoryNodesByIdProvider =
    Provider<AsyncValue<Map<String, CategoryNode>>>(
  (ref) => ref.watch(categoryTreeProvider).whenData(
        (tree) => {
          for (final node in CategoryTree.flatten(tree)) node.category.id: node,
        },
      ),
);
