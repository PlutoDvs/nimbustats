import 'package:drift/drift.dart';

import '../database/columns.dart';
import '../database/converters.dart';
import 'categories_table.dart';
import 'payment_methods_table.dart';

enum TxDirection { expense, income }

enum TxSource { manual, sms, notification, widget }

enum Necessity { needed, optional, avoidable }

enum Satisfaction { glad, neutral, regret }

/// Indexes are declared here rather than created with raw statements in the
/// migration, so they belong to drift's schema model and reach the exported
/// snapshot. `idx_tx_unconfirmed` is composite because the review queue asks
/// both questions at once: unconfirmed captures, most recent first.
@TableIndex(name: 'idx_tx_date', columns: {#localDateKey})
@TableIndex(name: 'idx_tx_category', columns: {#categoryId})
@TableIndex(name: 'idx_tx_unconfirmed', columns: {#isConfirmed, #localDateKey})
@TableIndex(name: 'idx_tx_merchant', columns: {#merchant})
class Transactions extends Table with BaseColumns {
  TextColumn get direction => textEnum<TxDirection>()();
  IntColumn get amount => integer().map(const MoneyConverter())();
  TextColumn get currencyCode => text().withLength(min: 3, max: 8)();

  IntColumn get occurredAtUtc => integer()();

  /// Local Gregorian yyyymmdd. Indexed; every period query is a range scan
  /// against this column in both calendars.
  IntColumn get localDateKey => integer().map(const DateKeyConverter())();
  IntColumn get tzOffsetMinutes => integer().withDefault(const Constant(0))();

  /// Required. A system "Uncategorized" row is used for captures awaiting
  /// review, so no chart ever has a hole in it.
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get paymentMethodId =>
      text().nullable().references(PaymentMethods, #id)();

  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();

  TextColumn get necessity => textEnum<Necessity>().nullable()();
  TextColumn get satisfaction => textEnum<Satisfaction>().nullable()();

  TextColumn get source => textEnum<TxSource>()();
  BoolColumn get isConfirmed => boolean().withDefault(const Constant(true))();
  TextColumn get captureId => text().nullable()();
}
