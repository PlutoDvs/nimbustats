import 'package:nimbus_domain/nimbus_domain.dart';

/// What a pin saves: a name, the question a tab is asking without its dates,
/// the window it covers, and how to draw it.
final class PinRequest {
  /// From the spec a tab is showing. Its date range is dropped here, in one
  /// place: the tab's range is the month on screen, while a pinned view means
  /// "the dashboard's month", which [period] carries.
  PinRequest.fromShown({
    required this.name,
    required QuerySpec shownSpec,
    required this.period,
    required this.chart,
  }) : spec = shownSpec.withDateRange(null);

  const PinRequest._(this.name, this.spec, this.period, this.chart);

  final String name;
  final QuerySpec spec;
  final ViewPeriod period;
  final SavedViewChart chart;

  /// The same request under the name the user typed.
  PinRequest named(String name) => PinRequest._(name, spec, period, chart);
}
