/// One past categorisation, reduced to the three fields a predictor reads.
///
/// Deliberately not a transaction row: a predictor has no business seeing
/// amounts or notes, and keeping the input this narrow is what lets the
/// interface live in `nimbus_domain` with no database dependency at all.
final class CategoryObservation {
  const CategoryObservation({
    required this.categoryId,
    required this.occurredAt,
    this.merchant,
  });

  final String categoryId;
  final DateTime occurredAt;
  final String? merchant;
}
