import 'package:nimbus_domain/nimbus_domain.dart';

/// One dashboard row, readable or not.
///
/// Sealed so the dashboard has to say what it draws for a row it cannot
/// read. Rows are read one at a time for exactly this: a single malformed
/// row used to fail the whole list, and one bad card must never blank the
/// dashboard (screen contract §5.1).
sealed class SavedViewEntry {
  const SavedViewEntry({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;
}

/// A stored view with its spec, period and chart parsed.
///
/// [spec] never carries a date range. [period] says which dates, relative to
/// wherever the dashboard is anchored, and the card puts them back.
final class SavedView extends SavedViewEntry {
  const SavedView({
    required super.id,
    required super.name,
    required super.sortOrder,
    required this.spec,
    required this.period,
    required this.chart,
  });

  final QuerySpec spec;
  final ViewPeriod period;
  final SavedViewChart chart;

  @override
  String toString() => 'SavedView($id, $name)';
}

/// A row whose spec, period or chart could not be parsed.
///
/// Carries the error instead of a substitute view: a default chart drawn
/// under the user's own name for something else looks like it worked, which
/// is worse than an honest "cannot read this".
final class UnreadableSavedView extends SavedViewEntry {
  const UnreadableSavedView({
    required super.id,
    required super.name,
    required super.sortOrder,
    required this.error,
  });

  final Object error;

  @override
  String toString() => 'UnreadableSavedView($id, $error)';
}

/// What `SavedViewsDao.create` writes.
typedef NewSavedView = ({
  String id,
  String name,
  QuerySpec spec,
  ViewPeriod period,
  SavedViewChart chart,
});
