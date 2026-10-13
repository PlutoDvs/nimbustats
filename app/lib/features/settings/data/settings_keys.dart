/// The `settings` table's key namespace.
///
/// String literals live here and nowhere else: a typo in a key is otherwise a
/// silent no-op, because an absent key reads back as "not configured yet"
/// rather than as an error.
abstract final class SettingsKeys {
  static const currencyCode = 'currency_code';
  static const calendarKind = 'calendar_kind';
  static const localeCode = 'locale';
  static const firstDayOfWeek = 'first_day_of_week';
  static const themeMode = 'theme_mode';
  static const onboardingCompleted = 'onboarding_completed';

  /// The keys `AppSettings` is read from -- and the only keys a settings reset
  /// clears.
  ///
  /// Every key parsed into `AppSettings` has to be here, including the
  /// onboarding flag: a corrupt value in any of them must be recoverable
  /// through reset. The keys below are facts about the install, written by
  /// first run and never parsed, so a reset leaves them alone.
  static const appSettings = {
    currencyCode,
    calendarKind,
    localeCode,
    firstDayOfWeek,
    themeMode,
    onboardingCompleted,
  };

  static const foundingUser = 'founding_user';
  static const installedAt = 'installed_at';

  /// Bumped when the seeded default tree changes, so a future phase can decide
  /// whether to re-seed. Phase 1 writes it and never reads it back.
  static const seedVersion = 'seed_version';

  /// Phase 6's notification settings. Outside [appSettings] on purpose: a
  /// settings reset must not leave a reminder armed in Android's alarm
  /// manager while the database says it is off (Phase 6 spec §8). Read by
  /// `NotificationPrefsRepository`, which reports a bad value and reads its
  /// default rather than failing.
  static const reminderEnabled = 'reminder_enabled';
  static const reminderMinuteOfDay = 'reminder_minute_of_day';
  static const notificationDetail = 'notification_detail';
}
