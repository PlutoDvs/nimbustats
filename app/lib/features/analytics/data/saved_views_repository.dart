import 'package:nimbus_data/nimbus_data.dart';

import 'pin_request.dart';

/// The app's only way to write a saved view.
final class SavedViewsRepository {
  const SavedViewsRepository(this._dao);

  final SavedViewsDao _dao;

  /// Pins [requests] to the end of the dashboard as one write, and returns
  /// the new views' ids in order. A blank name anywhere refuses the lot.
  Future<List<String>> pin(List<PinRequest> requests) async {
    final views = [
      for (final request in requests)
        (
          id: Ids.newId(),
          name: _validName(request.name),
          spec: request.spec,
          period: request.period,
          chart: request.chart,
        ),
    ];
    await _dao.create(views);
    return [for (final view in views) view.id];
  }

  /// The dashboard's cards, live, in the user's order.
  Stream<List<SavedViewEntry>> watchPinned() => _dao.watchPinned();

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A saved view needs a name');
    }
    return trimmed;
  }
}
