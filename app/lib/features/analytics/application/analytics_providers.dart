import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
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

/// How long one analytics query took, from asking to having the answer.
typedef QueryTimed = void Function(QuerySpec spec, Duration elapsed);

/// Where query timings go: what the device measurement reads.
///
/// Null in a release build, where nothing could listen, so no stopwatch is
/// even started. In debug and profile builds each timing is posted as a
/// `Nimbus.Query` VM service event -- the same channel, under the same guard,
/// that Flutter uses for its own `Flutter.Frame` timings -- for
/// `tool/frame_timings.dart` to collect from a running app. Posting with no
/// listener attached costs one check and returns.
final queryTimingProvider = Provider<QueryTimed?>(
  (ref) => kReleaseMode ? null : _postQueryTiming,
);

void _postQueryTiming(QuerySpec spec, Duration elapsed) =>
    developer.postEvent('Nimbus.Query', {
      'micros': elapsed.inMicroseconds,
      'spec': spec.toJson(),
    });

/// The answer to one question, keyed on the question itself.
///
/// The family key is a whole [QuerySpec], which works because the spec has
/// value equality -- the same property Phase 5 depends on to store one as a
/// goal's scope. Two widgets asking the same question therefore share one
/// query rather than each issuing their own.
///
/// Auto-disposed, and re-run whenever the engine reports a write to a table
/// it reads. It used to be neither: an answer was computed once and kept for
/// the life of the app, so a tab went on showing the total from before an
/// expense was added, and every month anyone looked at stayed in memory.
final analyticsResultProvider =
    FutureProvider.autoDispose.family<AnalyticsResult, QuerySpec>(
  (ref, spec) async {
    final engine = ref.watch(analyticsEngineProvider);
    final timed = ref.watch(queryTimingProvider);
    final changes = engine.changes().listen((_) => ref.invalidateSelf());
    ref.onDispose(changes.cancel);
    if (timed == null) return engine.run(spec);

    final stopwatch = Stopwatch()..start();
    final result = await engine.run(spec);
    timed(spec, stopwatch.elapsed);
    return result;
  },
);
