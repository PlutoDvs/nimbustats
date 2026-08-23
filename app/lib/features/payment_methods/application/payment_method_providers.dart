import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/payment_method_repository.dart';

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>(
  (ref) =>
      PaymentMethodRepository(ref.watch(appDatabaseProvider).paymentMethodsDao),
);

/// Every live payment method, archived included: the manager's view.
final paymentMethodsProvider = StreamProvider<List<PaymentMethod>>((ref) {
  ref.keepAlive();
  return ref.watch(paymentMethodRepositoryProvider).watchAll();
});

/// What the add screen offers: archived methods excluded.
final pickablePaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) {
    ref.keepAlive();
    return ref
        .watch(appDatabaseProvider)
        .paymentMethodsDao
        .watchAll(includeArchived: false);
  },
);
