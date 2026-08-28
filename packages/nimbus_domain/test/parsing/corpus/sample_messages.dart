/// Synthetic messages in the shape of Iranian bank SMS. Invented, not
/// captured — real message bodies are user data and do not belong in a
/// committed fixture.
library;

/// A message the purchase template is expected to parse, with what it should
/// yield. Amounts are in Toman after the template's amountScale is applied.
typedef ExpectedMatch = ({
  String label,
  String body,
  int amountMinorUnits,
  String? merchant,
});

/// A message from the same sender that must NOT parse. Each one is a shape a
/// greedy regex would happily swallow.
typedef NearMiss = ({String label, String body});

const purchaseSample = 'بانک نمونه\nخرید از فروشگاه رفاه\n'
    'مبلغ ۱۲,۵۰۰,۰۰۰ ریال\nمانده ۵۰,۰۰۰,۰۰۰\nتاریخ ۱۴۰۳/۰۵/۱۲';

const expectedMatches = <ExpectedMatch>[
  (
    label: 'the sample itself',
    body: purchaseSample,
    amountMinorUnits: 1250000,
    merchant: 'فروشگاه رفاه',
  ),
  (
    label: 'a different merchant, amount, balance and date',
    body: 'بانک نمونه خرید از قهوه ونک مبلغ ۹۸۷,۶۵۰ ریال '
        'مانده ۱,۱۱۱,۱۱۰ تاریخ ۱۴۰۳/۰۶/۰۱',
    amountMinorUnits: 98765,
    merchant: 'قهوه ونک',
  ),
  (
    label: 'Latin digits instead of Persian',
    body: 'بانک نمونه خرید از دیجی کالا مبلغ 5,000,000 ریال '
        'مانده 1,000,000 تاریخ 1403/07/02',
    amountMinorUnits: 500000,
    merchant: 'دیجی کالا',
  ),
  (
    label: 'a single-word merchant',
    body: 'بانک نمونه خرید از اسنپ مبلغ ۴۵۰,۰۰۰ ریال '
        'مانده ۲,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۳',
    amountMinorUnits: 45000,
    merchant: 'اسنپ',
  ),
];

const nearMisses = <NearMiss>[
  (
    label: 'a one-time password',
    body: 'بانک نمونه رمز پویا ۱۲۳۴۵ اعتبار ۲ دقیقه',
  ),
  (
    label: 'a balance-only notification',
    body: 'بانک نمونه مانده حساب شما ۵۰,۰۰۰,۰۰۰ ریال',
  ),
  (
    label: 'a loan advertisement carrying a large number',
    body: 'بانک نمونه وام ۵۰۰,۰۰۰,۰۰۰ ریالی ویژه مشتریان',
  ),
  (
    label: 'a deposit, which this template must not claim as a purchase',
    body: 'بانک نمونه واریز به حساب مبلغ ۱۲,۵۰۰,۰۰۰ ریال '
        'مانده ۵۰,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۲',
  ),
  (
    label: 'the purchase shape with trailing marketing text',
    body: 'بانک نمونه خرید از فروشگاه رفاه مبلغ ۱۲,۵۰۰,۰۰۰ ریال '
        'مانده ۵۰,۰۰۰,۰۰۰ تاریخ ۱۴۰۳/۰۵/۱۲ همراه بانک را نصب کنید',
  ),
];
