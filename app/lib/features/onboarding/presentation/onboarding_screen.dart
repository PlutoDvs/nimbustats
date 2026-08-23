import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/first_run.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/app_settings.dart';
import '../../transactions/routes.dart';

/// First run: three optional choices, and a way past them.
///
/// Every default is already valid before the first question is answered, so
/// nothing here can block reaching the add screen. That is the entire design --
/// a first-run flow that can be skipped is a first-run flow people finish.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late AppSettings _draft = AppSettings.defaults;
  bool _seeding = false;
  Object? _seedError;

  /// Persists the choices, seeds the category tree, and leaves.
  ///
  /// Seeding runs inside one transaction, so a failure leaves no half-built
  /// tree behind -- the retry starts from nothing rather than from a partial
  /// state that the emptiness check would mistake for "already done".
  Future<void> _finish({required bool skipped}) async {
    final router = GoRouter.of(context);
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(settingsRepositoryProvider);
    final firstRun = ref.read(firstRunControllerProvider);

    setState(() {
      _seeding = true;
      _seedError = null;
    });
    try {
      await repository.save(
        (skipped ? AppSettings.defaults : _draft)
            .copyWith(onboardingCompleted: true),
      );
      await firstRun.ensureSeeded(l10n);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _seeding = false;
          _seedError = error;
        });
      }
      return;
    }
    if (mounted) setState(() => _seeding = false);
    router.go(transactionListRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (_seedError != null) {
      return Scaffold(
        body: NimbusErrorState(
          title: l10n.onboardingSeedFailed,
          retryLabel: l10n.commonRetry,
          detail: _seedError.toString(),
          onRetry: () => _finish(skipped: false),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          children: [
            const SizedBox(height: NimbusTokens.space8),
            Text(
              l10n.onboardingWelcomeTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NimbusTokens.space2),
            Text(
              l10n.onboardingWelcomeBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NimbusTokens.space8),
            _Choice<Currency>(
              label: l10n.onboardingCurrencyTitle,
              value: _draft.currency,
              options: [
                for (final currency in Currency.all)
                  (
                    value: currency,
                    key: Key('onboarding-currency-${currency.code}'),
                    label: currency.code,
                  ),
              ],
              onSelected: (value) =>
                  setState(() => _draft = _draft.copyWith(currency: value)),
            ),
            _Choice<CalendarKind>(
              label: l10n.onboardingCalendarTitle,
              value: _draft.calendarKind,
              options: [
                (
                  value: CalendarKind.jalali,
                  key: const Key('onboarding-calendar-jalali'),
                  label: l10n.settingsCalendarJalali,
                ),
                (
                  value: CalendarKind.gregorian,
                  key: const Key('onboarding-calendar-gregorian'),
                  label: l10n.settingsCalendarGregorian,
                ),
              ],
              onSelected: (value) =>
                  setState(() => _draft = _draft.copyWith(calendarKind: value)),
            ),
            _Choice<Locale>(
              label: l10n.onboardingLocaleTitle,
              value: _draft.locale,
              options: const [
                (
                  value: Locale('fa'),
                  key: Key('onboarding-locale-fa'),
                  label: 'فارسی',
                ),
                (
                  value: Locale('en'),
                  key: Key('onboarding-locale-en'),
                  label: 'English',
                ),
              ],
              onSelected: (value) =>
                  setState(() => _draft = _draft.copyWith(locale: value)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: _seeding ? null : () => _finish(skipped: true),
                  child: Text(l10n.onboardingSkip),
                ),
              ),
              const SizedBox(width: NimbusTokens.space2),
              Expanded(
                child: SizedBox(
                  height: NimbusTokens.minTapTarget,
                  child: FilledButton(
                    key: const Key('onboarding-finish'),
                    onPressed: _seeding ? null : () => _finish(skipped: false),
                    child: Text(
                      _seeding ? l10n.onboardingSeeding : l10n.onboardingFinish,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _Option<T> = ({T value, Key key, String label});

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final T value;
  final List<_Option<T>> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: NimbusTokens.space2),
            Wrap(
              spacing: NimbusTokens.space2,
              children: [
                for (final option in options)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                        minHeight: NimbusTokens.chipHeight),
                    child: ChoiceChip(
                      key: option.key,
                      selected: option.value == value,
                      label: Text(option.label),
                      onSelected: (_) => onSelected(option.value),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
}
