import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/saved_views_repository.dart';

final savedViewsRepositoryProvider = Provider<SavedViewsRepository>(
  (ref) => SavedViewsRepository(ref.watch(appDatabaseProvider).savedViewsDao),
);

/// The dashboard's cards, live, in the user's order.
final pinnedViewsProvider = StreamProvider<List<SavedViewEntry>>(
  (ref) => ref.watch(savedViewsRepositoryProvider).watchPinned(),
);

/// One saved view, live, for its full screen. Auto-disposed: a closed screen
/// has no reason to keep watching.
final savedViewByIdProvider =
    StreamProvider.autoDispose.family<SavedViewEntry?, String>(
  (ref, id) => ref.watch(savedViewsRepositoryProvider).watchById(id),
);
