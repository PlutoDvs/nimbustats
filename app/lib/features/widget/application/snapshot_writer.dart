import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/data/app_settings.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/currency_label.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../trackers/data/tracker_clock.dart';
import '../../transactions/application/prediction_providers.dart';

/// Builds `widget_snapshot.json` (spec §6.1): everything the home-screen
/// widget and its dialog show, in the app's language. Native displays it
/// and never composes text.
///
/// One-shot reads only, settings included. The same code runs in the app
/// engine and in the headless drain engine, where no stream has emitted yet.
final class SnapshotWriter {
  const SnapshotWriter(this._db, this._clock);

  final AppDatabase _db;
  final TrackerClock _clock;

  static const version = 1;

  /// The largest layout's rows (spec §6.4).
  static const maxTrackers = 4;
  static const maxChips = 4;

  Future<String> build() async {
    // As every screen does while a stored setting is corrupt: the defaults,
    // while the settings screen surfaces the error and its reset
    // (settings_providers.dart). The drain, which stamps a currency, stays
    // strict instead.
    final settings = await SettingsRepository(_db.settingsDao)
        .load()
        .onError<SettingsFormatException>((_, __) => AppSettings.defaults);
    final l10n = lookupAppLocalizations(settings.locale);
    final today = _clock.today();
    final trackers = [
      for (final tracker in await _db.trackersDao.allLive(archived: false))
        // A timer cannot run from a widget (spec §6.1).
        if (tracker.type != TrackerType.duration) tracker,
    ].take(maxTrackers).toList();
    final totals = await _totals(trackers, today, settings.calendar);
    final language = settings.locale.languageCode;

    return jsonEncode({
      'v': version,
      // Gregorian, like every local_date_key: nothing here depends on the
      // calendar.
      'dayKey': today.value,
      'localeTag': language,
      'rtl': Bidi.isRtlLanguage(language),
      'currency': {
        'code': settings.currency.code,
        'decimalDigits': settings.currency.decimalDigits,
        'label': currencyLabel(l10n, settings.currency),
      },
      'trackers': [
        for (final tracker in trackers)
          {
            'id': tracker.id,
            'name': tracker.name,
            'color': tracker.color,
            'type': tracker.type.name,
            'perTap': TrackerValues.perTap(
              tracker.type,
              perTapValue: tracker.perTapValue,
            ),
            'unit': tracker.unit,
            'todayTotal': totals[tracker.id] ?? 0.0,
          },
      ],
      'chips': [
        for (final category in await _chips())
          {'id': category.id, 'name': category.name},
      ],
      'strings': {
        'addExpense': l10n.widgetAddExpense,
        'emptyTrackers': l10n.widgetEmptyTrackers,
        'entryTitle': l10n.widgetEntryTitle,
        'save': l10n.widgetSave,
        'cancel': l10n.widgetCancel,
        'saved': l10n.widgetSaved,
        // Templates: native fills the slots with values it formats itself
        // (spec §6.2), so a tap shows before the drain.
        'trackerAdd': l10n.widgetTrackerAdd('{name}', '{total}'),
        'trackerDone': l10n.widgetTrackerDone('{name}'),
      },
    });
  }

  Future<Map<String, double>> _totals(
    List<Tracker> trackers,
    DateKey today,
    AppCalendar calendar,
  ) async {
    if (trackers.isEmpty) return const {};
    final result = await AnalyticsEngine(_db, calendar: calendar).runTracker(
      TrackerQueries.dayTotals([for (final t in trackers) t.id], today),
    );
    return {
      for (final bucket in result.buckets)
        if (bucket.key case TrackerKey(:final trackerId))
          trackerId: bucket.value,
    };
  }

  /// The add screen's ranking, filtered as its chips are: live, unarchived,
  /// not a system row.
  Future<List<Category>> _chips() async {
    final predictor = await loadCategoryPredictor(_db);
    final offerable = {
      for (final category in await _db.categoriesDao.allLive(
        includeArchived: false,
      ))
        if (!SystemCategoryIds.isSystem(category.id)) category.id: category,
    };
    return [
      for (final id in predictor.predict(
        at: _clock.toLocal(_clock.nowUtc()),
        limit: maxChips,
      ))
        if (offerable[id] case final category?) category,
    ];
  }
}

final snapshotWriterProvider = Provider<SnapshotWriter>(
  (ref) => SnapshotWriter(
    ref.watch(appDatabaseProvider),
    ref.watch(trackerClockProvider),
  ),
);
