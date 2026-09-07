import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/routes.dart';
import '../../payment_methods/routes.dart';
import '../../tags/routes.dart';
import '../application/settings_providers.dart';
import '../data/app_settings.dart';
import 'widgets/demo_data_tile.dart';

/// Currency, calendar, locale, first day of week, theme -- and nothing else.
///
/// Every control writes through [SettingsRepository] and then re-reads. A
/// control that showed a value the database does not hold would be a lie the
/// user has no way to detect.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(settingsProvider);

    final Widget body;
    if (async.hasError) {
      // A stored value the app cannot parse. Not papered over with a default:
      // the user chose that setting once, and silently replacing it would hide
      // that something is wrong with their data.
      body = NimbusErrorState(
        title: l10n.settingsSaveFailed,
        retryLabel: l10n.settingsReset,
        detail: async.error.toString(),
        onRetry: () async {
          await ref.read(settingsRepositoryProvider).resetToDefaults();
          ref.invalidate(settingsProvider);
        },
      );
    } else if (async.value == null) {
      body = const NimbusLoadingList(rows: 6);
    } else {
      body = _Body(settings: async.value!);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: body,
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings});

  final AppSettings settings;

  /// Writes one change, and reverts nothing on success.
  ///
  /// On failure the control is left showing what the database still holds --
  /// the stream re-emits the unchanged value -- and the user is told. Screen
  /// contract 3.6: never display a value the database does not have.
  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    AppSettings next,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(settingsRepositoryProvider).save(next);
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsSaveFailed)),
      );
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      children: [
        ListTile(
          key: const Key('settings-pro'),
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(l10n.settingsProBadge),
          subtitle: Text(
            l10n.onboardingWelcomeBody,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const Divider(),
        _ChoiceTile<Currency>(
          tileKey: const Key('settings-currency'),
          title: l10n.settingsCurrency,
          value: settings.currency,
          options: [
            for (final currency in Currency.all)
              (
                value: currency,
                key: Key('currency-${currency.code.toLowerCase()}'),
                label: _currencyLabel(l10n, currency),
              ),
          ],
          onSelected: (value) =>
              _save(context, ref, settings.copyWith(currency: value)),
        ),
        _ChoiceTile<CalendarKind>(
          tileKey: const Key('settings-calendar'),
          title: l10n.settingsCalendar,
          value: settings.calendarKind,
          options: [
            (
              value: CalendarKind.jalali,
              key: const Key('calendar-jalali'),
              label: l10n.settingsCalendarJalali,
            ),
            (
              value: CalendarKind.gregorian,
              key: const Key('calendar-gregorian'),
              label: l10n.settingsCalendarGregorian,
            ),
          ],
          onSelected: (value) =>
              _save(context, ref, settings.copyWith(calendarKind: value)),
        ),
        _ChoiceTile<Locale>(
          tileKey: const Key('settings-locale'),
          title: l10n.settingsLocale,
          value: settings.locale,
          options: const [
            (
              value: Locale('fa'),
              key: Key('locale-fa'),
              label: 'فارسی',
            ),
            (
              value: Locale('en'),
              key: Key('locale-en'),
              label: 'English',
            ),
          ],
          onSelected: (value) =>
              _save(context, ref, settings.copyWith(locale: value)),
        ),
        _ChoiceTile<int>(
          tileKey: const Key('settings-first-day'),
          title: l10n.settingsFirstDayOfWeek,
          value: settings.firstDayOfWeek,
          options: [
            (
              value: DateTime.saturday,
              key: const Key('first-day-6'),
              label: l10n.weekdaySaturday
            ),
            (
              value: DateTime.sunday,
              key: const Key('first-day-7'),
              label: l10n.weekdaySunday
            ),
            (
              value: DateTime.monday,
              key: const Key('first-day-1'),
              label: l10n.weekdayMonday
            ),
          ],
          onSelected: (value) =>
              _save(context, ref, settings.copyWith(firstDayOfWeek: value)),
        ),
        _ChoiceTile<ThemeMode>(
          tileKey: const Key('settings-theme'),
          title: l10n.settingsTheme,
          value: settings.themeMode,
          options: [
            (
              value: ThemeMode.system,
              key: const Key('theme-system'),
              label: l10n.settingsThemeSystem,
            ),
            (
              value: ThemeMode.light,
              key: const Key('theme-light'),
              label: l10n.settingsThemeLight,
            ),
            (
              value: ThemeMode.dark,
              key: const Key('theme-dark'),
              label: l10n.settingsThemeDark,
            ),
          ],
          onSelected: (value) =>
              _save(context, ref, settings.copyWith(themeMode: value)),
        ),
        const Divider(),
        ListTile(
          key: const Key('settings-categories'),
          leading: const Icon(Icons.category_outlined),
          title: Text(l10n.categoryManagerTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(categoryManagerRoute),
        ),
        ListTile(
          key: const Key('settings-tags'),
          leading: const Icon(Icons.label_outline),
          title: Text(l10n.tagManagerTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(tagManagerRoute),
        ),
        ListTile(
          key: const Key('settings-payment-methods'),
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(l10n.payManagerTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(paymentMethodManagerRoute),
        ),
        const Divider(),
        ListTile(
          key: const Key('settings-reset'),
          leading: const Icon(Icons.restart_alt),
          title: Text(l10n.settingsReset),
          onTap: () async {
            await ref.read(settingsRepositoryProvider).resetToDefaults();
            ref.invalidate(settingsProvider);
          },
        ),
        // Debug builds only, and stripped from release by the constant: Task
        // 16 needs a device carrying 5,000 rows to measure the frame budget,
        // and a debug-only action is the difference between measuring that and
        // writing "not measured" in the definition of done.
        if (kDebugMode) const DemoDataTile(),
      ],
    );
  }

  static String _currencyLabel(AppLocalizations l10n, Currency currency) =>
      switch (currency.code) {
        'IRT' => l10n.currency_toman,
        'USD' => l10n.currency_usd,
        'EUR' => l10n.currency_eur,
        _ => l10n.currency_try,
      };
}

typedef _Option<T> = ({T value, Key key, String label});

/// A setting with a small, fixed set of answers.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.tileKey,
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final Key tileKey;
  final String title;
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((o) => o.value == value);

    return ListTile(
      key: tileKey,
      title: Text(title),
      subtitle: Text(selected.isEmpty ? '' : selected.first.label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final chosen = await showModalBottomSheet<T>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    key: option.key,
                    title: Text(option.label),
                    selected: option.value == value,
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          ),
        );
        if (chosen != null) onSelected(chosen);
      },
    );
  }
}
