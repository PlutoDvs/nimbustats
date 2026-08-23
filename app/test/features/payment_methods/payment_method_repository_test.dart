import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/payment_methods/data/payment_method_repository.dart';

void main() {
  late AppDatabase db;
  late PaymentMethodRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    repo = PaymentMethodRepository(db.paymentMethodsDao);
  });

  tearDown(() => db.close());

  test('last4 must be exactly four digits, or absent', () async {
    expect(
      () => repo.create(
          name: 'Card', kind: PaymentMethodKind.card, last4: '12'),
      throwsArgumentError,
    );

    final cash = await repo.create(name: 'Cash', kind: PaymentMethodKind.cash);
    expect(cash.last4, isNull);
  });

  test('Persian digits are normalised before they are stored', () async {
    // A user typing ۱۲۳۴ means 1234. Storing the Persian codepoints would make
    // the value unmatchable against an SMS capture in Phase 2.
    final method = await repo.create(
        name: 'Card', kind: PaymentMethodKind.card, last4: '۱۲۳۴');
    expect(method.last4, '1234');
  });

  test('the app never stores more than four digits', () async {
    expect(
      () => repo.create(
          name: 'Card',
          kind: PaymentMethodKind.card,
          last4: '1234567890123456'),
      throwsArgumentError,
      reason: 'this app has no reason to hold a full card number',
    );
  });

  test('four characters that are not all digits are rejected', () async {
    // The column would accept these -- it only constrains length -- so this is
    // the repository's job and nothing else's.
    expect(
      () => repo.create(
          name: 'Card', kind: PaymentMethodKind.card, last4: '12a4'),
      throwsArgumentError,
    );
  });

  test('a blank name is refused rather than stored', () async {
    expect(
      () => repo.create(name: '   ', kind: PaymentMethodKind.cash),
      throwsArgumentError,
    );
  });

  test('archived methods disappear from the picker but resolve historically',
      () async {
    final method =
        await repo.create(name: 'Old card', kind: PaymentMethodKind.card);
    await repo.archive(method.id);

    expect((await repo.pickable()).map((m) => m.id),
        isNot(contains(method.id)));
    // The transaction that used it still needs a label.
    expect(await repo.byId(method.id), isNotNull);
  });

  test('update validates last4 the same way create does', () async {
    final method =
        await repo.create(name: 'Card', kind: PaymentMethodKind.card);
    expect(() => repo.update(method.id, last4: '9'), throwsArgumentError);

    await repo.update(method.id, last4: '۹۸۷۶');
    expect((await repo.byId(method.id))!.last4, '9876');
  });

  test('delete reports what it removed so undo restores exactly that',
      () async {
    final method =
        await repo.create(name: 'Card', kind: PaymentMethodKind.card);
    final deleted = await repo.delete(method.id);
    expect(deleted, [method.id]);
    expect(await repo.watchAll().first, isEmpty);

    await repo.restore(deleted);
    expect((await repo.watchAll().first).single.id, method.id);
  });

  test('byId resolves a deleted method, because old transactions still point '
      'at it', () async {
    // byId is the label lookup, not a liveness check: a transaction paid from
    // a method the user later deleted must still render something other than a
    // blank. Liveness is what watchAll and pickable are for.
    final method =
        await repo.create(name: 'Card', kind: PaymentMethodKind.card);
    await repo.delete(method.id);
    expect(await repo.byId(method.id), isNotNull);
    expect((await repo.pickable()).map((m) => m.id),
        isNot(contains(method.id)));
  });
}
