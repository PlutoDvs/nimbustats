import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';

/// The localized name of [currency], as the settings tile and the widget
/// snapshot show it.
String currencyLabel(AppLocalizations l10n, Currency currency) =>
    switch (currency.code) {
      'IRT' => l10n.currency_toman,
      'USD' => l10n.currency_usd,
      'EUR' => l10n.currency_eur,
      _ => l10n.currency_try,
    };
