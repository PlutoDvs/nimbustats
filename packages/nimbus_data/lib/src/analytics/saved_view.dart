import 'package:nimbus_domain/nimbus_domain.dart';

/// A stored view with its `QuerySpec` already parsed.
///
/// The drift row carries `specJson`; this carries the spec. Parsing happens
/// once, in the DAO, so no caller can forget to do it and none of them can
/// disagree about what a malformed row means.
final class SavedView {
  const SavedView({
    required this.id,
    required this.name,
    required this.spec,
    required this.chartType,
    required this.pinned,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final QuerySpec spec;
  final String chartType;
  final bool pinned;
  final int sortOrder;

  @override
  String toString() => 'SavedView($id, $name)';
}
