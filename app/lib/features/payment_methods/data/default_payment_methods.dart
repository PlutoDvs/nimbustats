import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';

/// Ids of the payment methods first run creates.
///
/// Fixed strings, like the seeded category ids, so the add screen can tell
/// "only the defaults so far" from "the user has made one of their own" -- the
/// picker offers to add a method until the second is true.
abstract final class DefaultPaymentMethodIds {
  static const cash = 'seed-pay-cash';
  static const card = 'seed-pay-card';

  static bool isDefault(String id) => id == cash || id == card;
}

/// One method first run creates.
typedef DefaultPaymentMethod = ({
  String id,
  String name,
  PaymentMethodKind kind,
  String iconKey,
  int color,
});

/// Cash and Card, named in the language the install starts in.
///
/// Every capture can record how it was paid from the first launch, without a
/// trip to settings first -- an empty picker on the add screen reads as a
/// broken control. Like the category tree, these belong to the user once they
/// exist: renamed, archived or deleted as they like.
List<DefaultPaymentMethod> defaultPaymentMethods(AppLocalizations l10n) => [
      (
        id: DefaultPaymentMethodIds.cash,
        name: l10n.payKindCash,
        kind: PaymentMethodKind.cash,
        iconKey: 'payments',
        color: NimbusColors.swatch('green').toARGB32(),
      ),
      (
        id: DefaultPaymentMethodIds.card,
        name: l10n.payKindCard,
        kind: PaymentMethodKind.card,
        iconKey: 'credit_card',
        color: NimbusColors.swatch('blue').toARGB32(),
      ),
    ];
