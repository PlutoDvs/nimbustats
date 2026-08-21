import 'package:drift/drift.dart';

/// Key/value application settings. Deliberately not using BaseColumns --
/// settings are singleton values, not user records.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
