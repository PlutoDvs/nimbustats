import 'package:drift/drift.dart';

/// One SQL statement plus its bound variables.
///
/// The engine emits exactly one of these per `QuerySpec`. Keeping the SQL as
/// text rather than a drift query object is what lets Task 9 hand it to
/// `EXPLAIN QUERY PLAN` unchanged -- an index assertion against a *different*
/// statement than the one that runs would prove nothing.
///
/// Deliberately not annotated `@immutable`: `nimbus_data` does not depend on
/// `package:meta`, and the annotation would overstate the guarantee anyway,
/// since [variables] is a plain growable list handed straight to drift.
final class CompiledQuery {
  const CompiledQuery({required this.sql, required this.variables});

  final String sql;
  final List<Variable<Object>> variables;

  @override
  String toString() => 'CompiledQuery($sql)';
}
