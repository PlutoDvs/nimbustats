import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late PaymentMethodsDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.paymentMethodsDao;
    await dao.insertMethod(
      id: 'cash',
      name: 'Cash',
      kind: PaymentMethodKind.cash,
    );
    await dao.insertMethod(
      id: 'card',
      name: 'Blue card',
      kind: PaymentMethodKind.card,
      last4: '1234',
    );
  });

  tearDown(() => db.close());

  test('insertMethod round-trips every field', () async {
    final row = (await dao.byId('card'))!;
    expect(row.name, 'Blue card');
    expect(row.kind, PaymentMethodKind.card);
    expect(row.last4, '1234');
    expect(row.archived, isFalse);
  });

  test('the database itself refuses a last4 that is not four characters',
      () async {
    // withLength(min: 4, max: 4) is a CHECK constraint, so this cannot be
    // bypassed by any caller that skips the repository.
    expect(
      () => dao.insertMethod(
        id: 'bad',
        name: 'Bad',
        kind: PaymentMethodKind.card,
        last4: '12',
      ),
      throwsA(anything),
    );
  });

  test('updateMethod changes only what it is given', () async {
    await dao.updateMethod('card', name: 'Green card');
    var row = (await dao.byId('card'))!;
    expect(row.name, 'Green card');
    expect(row.last4, '1234');

    await dao.updateMethod('card', last4: '5678', color: 0xFF1565C0);
    row = (await dao.byId('card'))!;
    expect(row.last4, '5678');
    expect(row.color, 0xFF1565C0);
    expect(row.name, 'Green card');
  });

  test('archiving hides a method from the live list but keeps the row',
      () async {
    await dao.setArchived('card', true);
    expect((await dao.byId('card'))!.archived, isTrue);
    // Still resolvable: a transaction paid from this card last year must keep
    // its label, or the history stops making sense.
    expect(await dao.byId('card'), isNotNull);
    expect(await dao.allLive(includeArchived: true), hasLength(2));
    expect(await dao.allLive(includeArchived: false), hasLength(1));
  });

  test('soft delete removes it from live queries and undo restores it',
      () async {
    await dao.softDelete('card');
    expect(await dao.allLive(), hasLength(1));

    await dao.restoreAll(['card']);
    expect(await dao.allLive(), hasLength(2));
    expect((await dao.byId('card'))!.deletedAt, isNull);
  });

  test('watchAll emits on every write', () async {
    final seen = <int>[];
    final sub = dao.watchAll().listen((rows) => seen.add(rows.length));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await dao.insertMethod(
      id: 'bank',
      name: 'Bank',
      kind: PaymentMethodKind.bank,
    );
    await pumpEventQueue();

    expect(seen.first, 2);
    expect(seen.last, 3);
  });
}
