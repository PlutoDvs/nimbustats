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

/// `1405/07` for one month, `1405/02 – 1405/07` for a window.
String viewPeriodLabel(
  DateRange range,
  AppCalendar calendar, {
  required bool persianDigits,
}) {
  final first = periodLabel(range, calendar, persianDigits: persianDigits);
  final last = periodLabel(
    DateRange(range.endInclusive, range.endInclusive),
    calendar,
    persianDigits: persianDigits,
  );
  return first == last ? first : '$first – $last';
}

/// The caption over a total: "This month" while [range] is the month holding
/// [today], the range's own name otherwise.
///
/// A constant "This month" is right only where the period cannot move. The
/// breakdown tab has its own month bar and the full-screen view a shared one,
/// so both can show a past month under that caption; the cross-tab tab has no
/// period control at all, and there the caption is the only thing saying which
/// month is on screen. One function serves all three so the answer cannot
/// drift between them.
String totalCaption(
  DateRange range,
  AppCalendar calendar, {
  required DateKey today,
  required String thisMonth,
  required bool persianDigits,
}) =>
    range == calendar.periodContaining(today, PeriodType.month)
        ? thisMonth
        : viewPeriodLabel(range, calendar, persianDigits: persianDigits);
