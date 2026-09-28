import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/period_label.dart';

/// 2026-09-28 falls inside Jalali 1405/07, so the month before it is 1405/06
/// and the month after it 1405/08. The literals below are those months, not a
/// second implementation of the code under test.
void main() {
  const calendar = JalaliCalendar();
  final today = DateKey.fromDateTime(DateTime(2026, 9, 28));
  final currentMonth = calendar.periodContaining(today, PeriodType.month);

  String caption(DateRange range, {bool persianDigits = false}) => totalCaption(
        range,
        calendar,
        today: today,
        thisMonth: 'This month',
        persianDigits: persianDigits,
      );

  test('the month containing today is "this month"', () {
    expect(caption(currentMonth), 'This month');
  });

  test('a month back is named instead of called this month', () {
    expect(
      caption(calendar.shiftPeriod(currentMonth, PeriodType.month, -1)),
      '1405/06',
    );
  });

  test('a month ahead is named too', () {
    expect(
      caption(calendar.shiftPeriod(currentMonth, PeriodType.month, 1)),
      '1405/08',
    );
  });

  test('a window of months is named by its ends, not by its newest', () {
    expect(
      caption(ViewPeriod(PeriodType.month, 3).resolve(today, calendar)),
      '1405/05 – 1405/07',
    );
  });

  test('the name follows the money formatter into Persian digits', () {
    expect(
      caption(
        calendar.shiftPeriod(currentMonth, PeriodType.month, -1),
        persianDigits: true,
      ),
      '۱۴۰۵/۰۶',
    );
  });
}
