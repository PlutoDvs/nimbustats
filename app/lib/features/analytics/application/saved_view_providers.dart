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

/// The dashboard's card names, leaving out [exceptId]'s: what a name sheet
/// warns against reusing.
///
/// Read once, not watched: the sheet asks about the dashboard as it stands
/// when opened. The warning is advisory, so a list that has not loaded means
/// nothing to warn about rather than a pin that cannot start; a list that
/// failed to load is already reported by the dashboard itself.
Set<String> dashboardNames(WidgetRef ref, {String? exceptId}) => {
      for (final view
          in ref.read(pinnedViewsProvider).value ?? const <SavedViewEntry>[])
        if (view.id != exceptId) view.name,
    };

/// One saved view, live, for its full screen. Auto-disposed: a closed screen
/// has no reason to keep watching.
final savedViewByIdProvider =
    StreamProvider.autoDispose.family<SavedViewEntry?, String>(
  (ref, id) => ref.watch(savedViewsRepositoryProvider).watchById(id),
);
