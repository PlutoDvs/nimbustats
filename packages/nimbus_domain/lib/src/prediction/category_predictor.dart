/// Ranks category ids for a transaction the user has not categorised yet.
///
/// An interface rather than a function because Phase 2 replaces the Phase 1
/// implementation with merchant-rule-backed prediction, and the add screen must
/// not change when it does. The seam has to exist before the second
/// implementation arrives, or the screen ends up coupled to the first one.
abstract interface class CategoryPredictor {
  /// Returns up to [limit] category ids, best first.
  ///
  /// Never throws and never returns null: the add screen renders these as
  /// chips, and an empty list simply means no chips -- a normal first-run
  /// state rather than an error worth surfacing.
  List<String> predict({String? merchant, DateTime? at, int limit = 4});
}
