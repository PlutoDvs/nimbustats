import 'package:drift/drift.dart';

import '../database/columns.dart';

/// The index is declared here rather than created with a raw statement in the
/// migration, so that it is part of drift's schema model and therefore appears
/// in the exported schema snapshot.
@TableIndex(name: 'idx_categories_path', columns: {#path})
class Categories extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text().withDefault(const Constant('tag'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  /// Materialized path, e.g. `/food/dining/fast/`. Subtree rollup is then a
  /// range scan over this column rather than a recursive query.
  TextColumn get path => text()();
  IntColumn get depth => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}
