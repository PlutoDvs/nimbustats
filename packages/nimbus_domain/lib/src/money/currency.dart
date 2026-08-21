import 'package:meta/meta.dart';

/// A currency the app can operate in. Only one is active per install.
@immutable
final class Currency {
  const Currency({
    required this.code,
    required this.decimalDigits,
    required this.symbolKey,
  });

  /// ISO-style code. Toman uses `IRT`, which is not an ISO code — Iranian
  /// banks quote Rial (`IRR`) while people think and speak in Toman.
  final String code;

  /// Number of fractional digits. Toman has none.
  final int decimalDigits;

  /// Localization key for the symbol, resolved in the UI layer.
  final String symbolKey;

  static const toman =
      Currency(code: 'IRT', decimalDigits: 0, symbolKey: 'currency_toman');
  static const usd =
      Currency(code: 'USD', decimalDigits: 2, symbolKey: 'currency_usd');
  static const eur =
      Currency(code: 'EUR', decimalDigits: 2, symbolKey: 'currency_eur');
  static const tryLira =
      Currency(code: 'TRY', decimalDigits: 2, symbolKey: 'currency_try');

  static const all = <Currency>[toman, usd, eur, tryLira];

  static Currency byCode(String code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    throw ArgumentError.value(code, 'code', 'Unknown currency');
  }

  /// Multiplier converting one major unit into minor units.
  int get minorUnitsPerMajor {
    var result = 1;
    for (var i = 0; i < decimalDigits; i++) {
      result *= 10;
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Currency($code)';
}
