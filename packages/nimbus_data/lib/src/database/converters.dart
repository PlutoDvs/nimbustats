import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Stores a [DateKey] as its `yyyymmdd` integer, so period queries are indexed
/// range scans and no calendar math happens in SQL.
class DateKeyConverter extends TypeConverter<DateKey, int> {
  const DateKeyConverter();

  @override
  DateKey fromSql(int fromDb) => DateKey(fromDb);

  @override
  int toSql(DateKey value) => value.value;
}

/// Stores [Money] as minor units. No floating point ever reaches the database.
class MoneyConverter extends TypeConverter<Money, int> {
  const MoneyConverter();

  @override
  Money fromSql(int fromDb) => Money(fromDb);

  @override
  int toSql(Money value) => value.minorUnits;
}
