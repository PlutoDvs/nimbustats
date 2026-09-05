import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../settings/application/settings_providers.dart';

/// The app's only analytics query path.
///
/// There is deliberately no `AnalyticsRepository` beside this. The other
/// features have one because a repository earns its place there: it wraps raw
/// DAOs and adds policy the screens must not be able to skip -- the stamped
/// currency, the Uncategorized fallback, tag usage counts. `AnalyticsEngine`
/// already *is* that layer, so a class forwarding `run` to it would add a name
/// and no guarantee.
///
/// [calendarProvider] is watched rather than read: a Jalali month is not a
/// Gregorian one, so switching calendars has to rebuild the engine and re-run
/// every open chart. Read once, the app would keep bucketing by the calendar
/// that happened to be active at startup.
final analyticsEngineProvider = Provider<AnalyticsEngine>(
  (ref) => AnalyticsEngine(
    ref.watch(appDatabaseProvider),
    calendar: ref.watch(calendarProvider),
  ),
);

/// The answer to one question, keyed on the question itself.
///
/// The family key is a whole [QuerySpec], which works because the spec has
/// value equality -- the same property Phase 5 depends on to store one as a
/// goal's scope. Two widgets asking the same question therefore share one
/// query rather than each issuing their own.
final analyticsResultProvider =
    FutureProvider.family<AnalyticsResult, QuerySpec>(
  (ref, spec) => ref.watch(analyticsEngineProvider).run(spec),
);
