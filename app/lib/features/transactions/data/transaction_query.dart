import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Where the last page stopped.
///
/// A position in the ordering, not a row offset. That is the whole point: it
/// stays valid when rows are inserted or deleted around it, which an offset
/// does not.
final class TransactionCursor {
  const TransactionCursor({required this.dateKey, required this.id});

  factory TransactionCursor.of(Transaction transaction) => TransactionCursor(
        dateKey: transaction.localDateKey,
        id: transaction.id,
      );

  final DateKey dateKey;
  final String id;

  TransactionCursorRow get row => (dateKey: dateKey, id: id);

  @override
  bool operator ==(Object other) =>
      other is TransactionCursor && other.dateKey == dateKey && other.id == id;

  @override
  int get hashCode => Object.hash(dateKey, id);

  @override
  String toString() => 'TransactionCursor($dateKey, $id)';
}

/// One page's worth of request.
///
/// Immutable, so a screen holds the query it asked for and asks for the next
/// page with [next] rather than mutating shared state under a scroll listener.
final class PaginatedTransactionQuery {
  const PaginatedTransactionQuery({
    required this.range,
    this.cursor,
    this.limit = 40,
    this.direction,
    this.categoryId,
    this.searchText,
    this.confirmedOnly = false,
  }) : assert(limit > 0, 'A page must ask for at least one row');

  final DateRange range;
  final TransactionCursor? cursor;
  final int limit;
  final TxDirection? direction;
  final String? categoryId;
  final String? searchText;
  final bool confirmedOnly;

  /// The same query, continued from [cursor].
  ///
  /// Every filter is carried over deliberately: a "next page" that quietly
  /// dropped the active filter would serve rows the user has excluded, and it
  /// would look like a pagination bug rather than a filter one.
  PaginatedTransactionQuery next(TransactionCursor cursor) =>
      PaginatedTransactionQuery(
        range: range,
        cursor: cursor,
        limit: limit,
        direction: direction,
        categoryId: categoryId,
        searchText: searchText,
        confirmedOnly: confirmedOnly,
      );
}

/// One page's worth of answer.
final class TransactionPage {
  const TransactionPage({required this.items, required this.cursor});

  final List<Transaction> items;

  /// Where to continue from, or null when this was the last page.
  ///
  /// Null rather than "the last row's position" so that `hasMore` is a fact
  /// the repository established by looking, not a guess the caller makes from
  /// `items.length == limit` -- which is wrong exactly when the total happens
  /// to be a multiple of the page size.
  final TransactionCursor? cursor;

  bool get hasMore => cursor != null;
}
