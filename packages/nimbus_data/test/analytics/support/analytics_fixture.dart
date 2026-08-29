import 'package:nimbus_data/nimbus_data.dart';

/// Seeds the shared analytics fixture. Numbers in the tests are hand-computed
/// from these rows; changing them means recomputing every expectation.
Future<void> seedAnalyticsFixture(AppDatabase db) async {
  Future<void> tag(String id, String path, int depth) => db.customStatement(
        'INSERT INTO tags (id,name,icon_key,color,parent_id,path,depth,'
        'sort_order,usage_count,archived,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
        [id, id, 'tag', 0, null, path, depth, 0, 0, 0, 1, 1],
      );

  await tag('travel', '/travel/', 0);
  await tag('flights', '/travel/flights/', 1);
  await tag('food', '/food/', 0);

  await db.customStatement(
    'INSERT INTO categories (id,name,icon_key,color,parent_id,path,depth,'
    'sort_order,kind,archived,created_at,updated_at,deleted_at) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
    ['cat', 'cat', 'tag', 0, null, '/cat/', 0, 0, 'expense', 0, 1, 1],
  );

  Future<void> tx(String id, int amount, int dateKey) => db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,NULL,?,1,NULL,?,?,NULL)',
        [id, 'expense', amount, 'IRT', 0, dateKey, 0, 'cat', 'manual', 1, 1],
      );

  await tx('t1', 1000, 20260115);
  await tx('t2', 500, 20260220);
  await tx('t3', 250, 20260315);

  Future<void> link(String txId, String tagId) => db.customStatement(
      'INSERT INTO transaction_tags (transaction_id,tag_id) VALUES (?,?)',
      [txId, tagId]);

  await link('t1', 'travel');
  await link('t1', 'food');
  await link('t2', 'flights');
  await link('t2', 'travel');
}
