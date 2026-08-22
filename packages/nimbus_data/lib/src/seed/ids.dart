import 'package:uuid/uuid.dart';

/// Identifier generation for every row the app creates.
///
/// UUIDv7 rather than v4: the leading 48 bits are a millisecond timestamp, so
/// ids sort chronologically. That makes them index-friendly as a primary key,
/// and gives keyset pagination a meaningful tiebreaker for two transactions
/// that fall on the same local date.
abstract final class Ids {
  static const _uuid = Uuid();

  static String newId() => _uuid.v7();
}
