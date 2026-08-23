import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import '../data/transaction_query.dart';
import 'transaction_providers.dart';

/// One day's worth of rows, with its subtotal computed once.
///
/// The subtotal covers the rows actually loaded for that day. That is honest
/// -- a day is always fully loaded, because pages are ordered by date and a
/// day boundary is never split across two of them once the page containing it
/// has arrived. The *month* total is a different question and is answered by
/// SQL, not by adding these up.
final class TransactionDayGroup {
  TransactionDayGroup({required this.day, required this.rows})
      : subtotal = Money.sum(
          rows
              .where((r) => r.direction == TxDirection.expense)
              .map((r) => r.amount),
        );

  final DateKey day;
  final List<Transaction> rows;
  final Money subtotal;
}

final class TransactionListState {
  const TransactionListState({
    required this.period,
    required this.groups,
    required this.monthTotal,
    this.cursor,
    this.isLoadingMore = false,
    this.searchText,
    this.direction,
    this.categoryId,
  });

  final DateRange period;
  final List<TransactionDayGroup> groups;

  /// A SQL SUM over the whole period, not the sum of what happens to be
  /// loaded. Confusing the two produces a number that looks right until
  /// somebody scrolls.
  final Money monthTotal;

  final TransactionCursor? cursor;
  final bool isLoadingMore;
  final String? searchText;
  final TxDirection? direction;
  final String? categoryId;

  bool get hasMore => cursor != null;

  bool get isEmpty => groups.isEmpty;

  int get rowCount =>
      groups.fold(0, (total, group) => total + group.rows.length);

  List<Transaction> get rows => [for (final g in groups) ...g.rows];
}

/// Drives the transaction list: one period at a time, one page at a time.
class TransactionListController extends AsyncNotifier<TransactionListState> {
  static const pageSize = 40;

  @override
  Future<TransactionListState> build() {
    // Boundaries come from the active calendar, so a Jalali month is Mordad
    // rather than August and nothing else in this file needs to know that.
    final calendar = ref.watch(calendarProvider);
    final period = calendar.periodContaining(
      DateKey.fromDateTime(DateTime.now()),
      PeriodType.month,
    );
    return _load(period: period);
  }

  Future<TransactionListState> _load({
    required DateRange period,
    String? searchText,
    TxDirection? direction,
    String? categoryId,
  }) async {
    final repository = ref.read(transactionRepositoryProvider);
    final page = await repository.page(PaginatedTransactionQuery(
      range: period,
      limit: pageSize,
      searchText: searchText,
      direction: direction,
      categoryId: categoryId,
    ));
    final total = await repository.total(
      period,
      direction: direction ?? TxDirection.expense,
    );

    return TransactionListState(
      period: period,
      groups: _group(page.items),
      monthTotal: total,
      cursor: page.cursor,
      searchText: searchText,
      direction: direction,
      categoryId: categoryId,
    );
  }

  /// Appends the next page.
  ///
  /// Guarded by [TransactionListState.isLoadingMore]: a fling issues scroll
  /// callbacks far faster than a page resolves, and three overlapping requests
  /// would append the same rows three times.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(_copy(current, isLoadingMore: true));
    final page = await ref.read(transactionRepositoryProvider).page(
          PaginatedTransactionQuery(
            range: current.period,
            cursor: current.cursor,
            limit: pageSize,
            searchText: current.searchText,
            direction: current.direction,
            categoryId: current.categoryId,
          ),
        );

    state = AsyncData(TransactionListState(
      period: current.period,
      groups: _group([...current.rows, ...page.items]),
      monthTotal: current.monthTotal,
      cursor: page.cursor,
      searchText: current.searchText,
      direction: current.direction,
      categoryId: current.categoryId,
    ));
  }

  Future<void> setPeriod(DateRange period) => _replace(period: period);

  Future<void> shiftPeriod(int delta) async {
    final current = state.value;
    if (current == null) return;
    final calendar = ref.read(calendarProvider);
    await _replace(
      period: calendar.shiftPeriod(current.period, PeriodType.month, delta),
    );
  }

  Future<void> setSearch(String? text) =>
      _replace(searchText: (text?.trim().isEmpty ?? true) ? null : text);

  Future<void> setFilters({TxDirection? direction, String? categoryId}) =>
      _replace(direction: direction, categoryId: categoryId, clearFilters: true);

  Future<void> refresh() => _replace();

  /// Reloads from the first page.
  ///
  /// Any change to the period or the filters invalidates the cursor: it is a
  /// position in a specific ordering, and continuing from it under different
  /// criteria would splice two different result sets together.
  Future<void> _replace({
    DateRange? period,
    String? searchText,
    TxDirection? direction,
    String? categoryId,
    bool clearFilters = false,
  }) async {
    final current = state.value;
    if (current == null) return;

    // The previous data is deliberately left in place while the new query
    // runs. A period change resolves in milliseconds against a local database,
    // and blanking the list to a skeleton in between reads as a flicker rather
    // than as progress.
    state = await AsyncValue.guard(() => _load(
          period: period ?? current.period,
          searchText: searchText ?? current.searchText,
          direction: clearFilters ? direction : direction ?? current.direction,
          categoryId:
              clearFilters ? categoryId : categoryId ?? current.categoryId,
        ));
  }

  static TransactionListState _copy(
    TransactionListState from, {
    bool? isLoadingMore,
  }) =>
      TransactionListState(
        period: from.period,
        groups: from.groups,
        monthTotal: from.monthTotal,
        cursor: from.cursor,
        isLoadingMore: isLoadingMore ?? from.isLoadingMore,
        searchText: from.searchText,
        direction: from.direction,
        categoryId: from.categoryId,
      );

  /// Groups by local date key, preserving the newest-first order the query
  /// already established. Computed once per page rather than per build.
  static List<TransactionDayGroup> _group(List<Transaction> rows) {
    final groups = <TransactionDayGroup>[];
    var index = 0;
    while (index < rows.length) {
      final day = rows[index].localDateKey;
      final slice = <Transaction>[];
      while (index < rows.length && rows[index].localDateKey == day) {
        slice.add(rows[index]);
        index++;
      }
      groups.add(TransactionDayGroup(day: day, rows: slice));
    }
    return groups;
  }
}

final transactionListControllerProvider =
    AsyncNotifierProvider<TransactionListController, TransactionListState>(
  TransactionListController.new,
);
