import 'package:nimbus_domain/nimbus_domain.dart';

/// A period as `year/month`, in the active calendar's own numbering.
///
/// Numeric rather than a month name, deliberately. Month names would need a
/// table for two calendar systems in two languages -- 48 strings to translate
/// and keep in step -- and a trend axis has no width for "Shahrivar" beside
/// five others. Numerals carry the same information and read correctly in
/// both scripts.
String periodLabel(
  DateRange period,
  AppCalendar calendar, {
  required bool persianDigits,
}) {
  final parts = calendar.partsOf(period.startInclusive);
  final text = '${parts.year}/${parts.month.toString().padLeft(2, '0')}';
  return persianDigits ? Digits.toPersian(text) : text;
}
