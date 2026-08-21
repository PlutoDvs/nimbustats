import 'package:drift/drift.dart';

import 'tags_table.dart';
import 'transactions_table.dart';

/// Join table. The composite primary key is what makes attaching the same tag
/// twice impossible in the database rather than only in the DAO.
@TableIndex(name: 'idx_txtags_tag', columns: {#tagId})
class TransactionTags extends Table {
  /// Cascades: deleting a transaction takes its tag links with it, enforced by
  /// the database instead of by every call site remembering to do it.
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id)();

  @override
  Set<Column<Object>> get primaryKey => {transactionId, tagId};
}
