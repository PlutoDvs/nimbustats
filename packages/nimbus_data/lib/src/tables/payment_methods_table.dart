import 'package:drift/drift.dart';

import '../database/columns.dart';

enum PaymentMethodKind { cash, card, bank, other }

class PaymentMethods extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<PaymentMethodKind>()();

  /// Last four digits, for recognising a card in a capture. Never the full
  /// number -- this app has no reason to hold one.
  TextColumn get last4 => text().withLength(min: 4, max: 4).nullable()();
  IntColumn get color => integer().withDefault(const Constant(0xFF9E9E9E))();
  TextColumn get iconKey => text().withDefault(const Constant('card'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}
