import 'package:drift/native.dart';
import 'package:nimbus_data/nimbus_data.dart';

/// An in-memory database, fresh per test.
///
/// Every test gets its own connection, so tests never share rows and can run
/// in any order.
AppDatabase openTestDatabase() => AppDatabase(NativeDatabase.memory());
