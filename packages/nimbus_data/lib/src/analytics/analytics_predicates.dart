import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../tables/transactions_table.dart';
import '../tree/materialized_path.dart';

/// Filter translation, and the boundary between the two enum families.
///
/// `nimbus_domain` cannot import `nimbus_data`, so `QuerySpec` names
/// `MoneyDirection` / `NecessityLevel` / `SatisfactionLevel` while the table
/// declares `TxDirection` / `Necessity` / `Satisfaction`. The mapping happens
/// here, once, and `predicates_test.dart` fails if either family gains a value
/// the other lacks.
abstract final class AnalyticsPredicates {
  /// The one place the soft-delete rule is written for the engine.
  ///
  /// A single query that forgets this resurrects deleted rows in exactly one
  /// chart, which is the kind of bug that gets reported as "the numbers are
  /// wrong somewhere".
  static String notDeleted(String alias) => '$alias.deleted_at IS NULL';

  static TxDirection directionOf(MoneyDirection value) => switch (value) {
        MoneyDirection.expense => TxDirection.expense,
        MoneyDirection.income => TxDirection.income,
      };

  static Necessity necessityOf(NecessityLevel value) => switch (value) {
        NecessityLevel.needed => Necessity.needed,
        NecessityLevel.optional => Necessity.optional,
        NecessityLevel.avoidable => Necessity.avoidable,
      };

  static Satisfaction satisfactionOf(SatisfactionLevel value) =>
      switch (value) {
        SatisfactionLevel.glad => Satisfaction.glad,
        SatisfactionLevel.neutral => Satisfaction.neutral,
        SatisfactionLevel.regret => Satisfaction.regret,
      };

  /// Builds the WHERE clause for [filters], against the transactions table
  /// aliased as `t`.
  static ({String sql, List<Variable<Object>> variables}) whereClause(
    QueryFilters filters,
  ) {
    final conditions = <String>[notDeleted('t')];
    final variables = <Variable<Object>>[];

    final range = filters.dateRange;
    if (range != null) {
      conditions.add('t.local_date_key BETWEEN ? AND ?');
      variables
        ..add(Variable.withInt(range.startInclusive.value))
        ..add(Variable.withInt(range.endInclusive.value));
    }

    final direction = filters.direction;
    if (direction != null) {
      conditions.add('t.direction = ?');
      variables.add(Variable.withString(directionOf(direction).name));
    }

    if (filters.categorySubtreePaths.isNotEmpty) {
      final clauses = <String>[];
      for (final path in filters.categorySubtreePaths) {
        clauses.add('EXISTS (SELECT 1 FROM categories c '
            'WHERE c.id = t.category_id AND c.path >= ? AND c.path < ?)');
        variables
          ..add(Variable.withString(path))
          ..add(Variable.withString(MaterializedPath.subtreeUpperBound(path)));
      }
      conditions.add('(${clauses.join(' OR ')})');
    }

    if (filters.paymentMethodIds.isNotEmpty) {
      final placeholders =
          List.filled(filters.paymentMethodIds.length, '?').join(',');
      conditions.add('t.payment_method_id IN ($placeholders)');
      variables.addAll(filters.paymentMethodIds.map(Variable.withString));
    }

    if (filters.necessity.isNotEmpty) {
      final placeholders = List.filled(filters.necessity.length, '?').join(',');
      conditions.add('t.necessity IN ($placeholders)');
      variables.addAll(
          filters.necessity.map((n) => Variable.withString(necessityOf(n).name)));
    }

    if (filters.satisfaction.isNotEmpty) {
      final placeholders =
          List.filled(filters.satisfaction.length, '?').join(',');
      conditions.add('t.satisfaction IN ($placeholders)');
      variables.addAll(filters.satisfaction
          .map((s) => Variable.withString(satisfactionOf(s).name)));
    }

    final amounts = filters.amountRange;
    if (amounts != null) {
      final min = amounts.minInclusive;
      if (min != null) {
        conditions.add('t.amount >= ?');
        variables.add(Variable.withInt(min.minorUnits));
      }
      final max = amounts.maxInclusive;
      if (max != null) {
        conditions.add('t.amount <= ?');
        variables.add(Variable.withInt(max.minorUnits));
      }
    }

    if (filters.confirmedOnly) {
      conditions.add('t.is_confirmed = 1');
    }

    final needle = filters.searchText?.trim();
    if (needle != null && needle.isNotEmpty) {
      // Wildcards in user input match literally, the same way Phase 1's
      // transaction search already escapes them. Without this, typing `%`
      // silently matches everything and the search stops being a search.
      final escaped = needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      conditions
          .add(r"(t.merchant LIKE ? ESCAPE '\' OR t.note LIKE ? ESCAPE '\')");
      variables
        ..add(Variable.withString('%$escaped%'))
        ..add(Variable.withString('%$escaped%'));
    }

    final tags = filters.tags;
    if (tags != null) {
      conditions.add(_tagCondition(tags, variables));
    }

    return (sql: conditions.join(' AND '), variables: variables);
  }

  /// Tag conditions are `EXISTS` subqueries, never joins.
  ///
  /// A join multiplies the row: a transaction carrying both `/travel/` and its
  /// child `/travel/flights/` would be counted twice, and its amount summed
  /// twice. Measured on the fixture, the join answers 2000 where the truth is
  /// 1500.
  static String _tagCondition(
      TagFilter filter, List<Variable<Object>> variables) {
    String existsFor(String path) {
      variables
        ..add(Variable.withString(path))
        ..add(Variable.withString(MaterializedPath.subtreeUpperBound(path)));
      return 'EXISTS (SELECT 1 FROM transaction_tags tt '
          'JOIN tags tg ON tg.id = tt.tag_id '
          'WHERE tt.transaction_id = t.id AND ${notDeleted('tg')} '
          'AND tg.path >= ? AND tg.path < ?)';
    }

    // `.toList()` forces the side-effecting `existsFor` to run in placeholder
    // order. `map` is lazy; deferring it would silently shift every binding.
    return switch (filter) {
      TagsAll(:final subtreePaths) =>
        '(${subtreePaths.map(existsFor).toList().join(' AND ')})',
      TagsAny(:final subtreePaths) =>
        '(${subtreePaths.map(existsFor).toList().join(' OR ')})',
      TagsNone(:final subtreePaths) =>
        '(NOT (${subtreePaths.map(existsFor).toList().join(' OR ')}))',
    };
  }
}
