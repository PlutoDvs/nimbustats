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

  /// One view, live; null once removed.
  Stream<SavedViewEntry?> watchById(String id) => _dao.watchById(id);

  Future<void> rename(String id, String name) =>
      _dao.rename(id, _validName(name));

  /// [ids] is every pinned view, in the new order.
  Future<void> reorder(List<String> ids) => _dao.reorder(ids);

  Future<void> remove(String id) => _dao.softDelete(id);

  /// The undo behind [remove].
  Future<void> restore(String id) => _dao.restore(id);

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A saved view needs a name');
    }
    return trimmed;
  }
}
