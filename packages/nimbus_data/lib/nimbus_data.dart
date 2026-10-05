/// Pure-Dart persistence layer for NimbuStats.
///
/// Exports are added one per line and kept alphabetically sorted so that
/// concurrent phases appending to this barrel merge cleanly.
library;

export 'src/analytics/analytics_engine.dart';
export 'src/analytics/analytics_predicates.dart';
export 'src/analytics/compiled_query.dart';
export 'src/analytics/group_expressions.dart';
export 'src/analytics/saved_view.dart';
export 'src/database/app_database.dart';
export 'src/database/columns.dart';
export 'src/database/converters.dart';
export 'src/seed/category_seeder.dart';
export 'src/seed/ids.dart';
export 'src/seed/seed_category.dart';
export 'src/tables/payment_methods_table.dart';
export 'src/tables/transactions_table.dart';
export 'src/trackers/tracker_entries_dao.dart';
export 'src/trackers/trackers_dao.dart';
export 'src/tree/materialized_path.dart';
