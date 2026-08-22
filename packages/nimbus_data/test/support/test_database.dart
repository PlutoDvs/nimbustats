import 'package:nimbus_data/nimbus_data.dart';

/// An in-memory database, fresh per test.
///
/// Every test gets its own connection, so tests never share rows and can run
/// in any order. Delegates to [AppDatabase.openInMemory] rather than building
/// a [NativeDatabase] here, so there is exactly one place that decides how a
/// database is opened.
AppDatabase openTestDatabase() => AppDatabase.openInMemory();
