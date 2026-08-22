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
  static const foundingUser = 'founding_user';
  static const installedAt = 'installed_at';

  /// Bumped when the seeded default tree changes, so a future phase can decide
  /// whether to re-seed. Phase 1 writes it and never reads it back.
  static const seedVersion = 'seed_version';
}
