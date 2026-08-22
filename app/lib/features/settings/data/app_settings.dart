import 'package:flutter/material.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// The handful of choices that decide how everything else in the app renders.
///
/// Immutable and compared by value, so a settings stream can be deduplicated
/// and a round-trip through the database can be asserted with a single
/// equality check rather than field by field.
@immutable
final class AppSettings {
  const AppSettings({
    required this.currency,
    required this.calendarKind,
    required this.locale,
    required this.firstDayOfWeek,
    required this.themeMode,
    required this.onboardingCompleted,
  });

  /// What a first run gets before the user has answered anything.
  ///
  /// Farsi, Jalali, and Toman are the primary experience rather than a
  /// fallback, and Saturday is the first day of the week that goes with them.
  /// Onboarding can be skipped entirely because these values are already
  /// coherent -- nothing in the app has to wait for them to be confirmed.
  static const defaults = AppSettings(
    currency: Currency.toman,
    calendarKind: CalendarKind.jalali,
    locale: Locale('fa'),
    firstDayOfWeek: DateTime.saturday,
    themeMode: ThemeMode.system,
    onboardingCompleted: false,
  );

  /// Locales the app actually has an ARB bundle for. A value outside this set
  /// is rejected rather than accepted and silently rendered in English.
  static const supportedLanguageCodes = {'fa', 'en'};

  final Currency currency;
  final CalendarKind calendarKind;
  final Locale locale;

  /// ISO weekday, `DateTime.monday` (1) through `DateTime.sunday` (7) --
  /// matching `DateKey.weekday` and both [AppCalendar] implementations, so no
  /// conversion is needed at any call site.
  final int firstDayOfWeek;

  final ThemeMode themeMode;
  final bool onboardingCompleted;

  /// The calendar every period calculation goes through.
  AppCalendar get calendar => switch (calendarKind) {
        CalendarKind.jalali => const JalaliCalendar(),
        CalendarKind.gregorian => const GregorianCalendar(),
      };

  /// Numerals follow the locale, not the calendar. A user may read English and
  /// keep the Jalali calendar; both combinations have to render correctly.
  bool get persianDigits => locale.languageCode == 'fa';

  MoneyFormatter get moneyFormatter =>
      MoneyFormatter(currency: currency, persianDigits: persianDigits);

  AppSettings copyWith({
    Currency? currency,
    CalendarKind? calendarKind,
    Locale? locale,
    int? firstDayOfWeek,
    ThemeMode? themeMode,
    bool? onboardingCompleted,
  }) =>
      AppSettings(
        currency: currency ?? this.currency,
        calendarKind: calendarKind ?? this.calendarKind,
        locale: locale ?? this.locale,
        firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
        themeMode: themeMode ?? this.themeMode,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.currency == currency &&
      other.calendarKind == calendarKind &&
      other.locale == locale &&
      other.firstDayOfWeek == firstDayOfWeek &&
      other.themeMode == themeMode &&
      other.onboardingCompleted == onboardingCompleted;

  @override
  int get hashCode => Object.hash(currency, calendarKind, locale,
      firstDayOfWeek, themeMode, onboardingCompleted);

  @override
  String toString() => 'AppSettings(${currency.code}, ${calendarKind.name}, '
      '${locale.languageCode}, firstDay: $firstDayOfWeek, '
      '${themeMode.name}, onboarded: $onboardingCompleted)';
}
