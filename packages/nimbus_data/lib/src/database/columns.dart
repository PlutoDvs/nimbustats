import 'package:drift/drift.dart';

/// Columns every table carries. UUIDv7 ids are time-ordered, so they index
/// well and remain stable if data ever has to merge across devices.
mixin BaseColumns on Table {
  TextColumn get id => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
