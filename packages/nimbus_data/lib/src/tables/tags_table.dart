import 'package:drift/drift.dart';

import '../database/columns.dart';

@TableIndex(name: 'idx_tags_path', columns: {#path})
class Tags extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text().withDefault(const Constant('tag'))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  TextColumn get parentId => text().nullable().references(Tags, #id)();

  /// Same format and same reasoning as `Categories.path`.
  TextColumn get path => text()();
  IntColumn get depth => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get usageCount => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}
