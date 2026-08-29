import 'package:drift/drift.dart';

import '../database/columns.dart';

/// A named `QuerySpec` the user pinned.
///
/// The spec is stored as JSON rather than as columns because `QuerySpec` is
/// already a lossless JSON value -- Phase 5 stores one as a goal's scope too --
/// and shredding it into columns would mean a migration every time the spec
/// grows a filter.
/// The generated row class is named explicitly: drift would otherwise call
/// it `SavedView`, which is the name of the parsed value type callers
/// actually want (see `../analytics/saved_view.dart`).
@DataClassName('SavedViewRow')
@TableIndex(name: 'idx_saved_views_pinned', columns: {#pinned, #sortOrder})
class SavedViews extends Table with BaseColumns {
  TextColumn get name => text()();

  /// A serialized `QuerySpec`.
  TextColumn get specJson => text()();

  TextColumn get chartType => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
