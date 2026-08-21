import 'feature.dart';

abstract interface class EntitlementSource {
  Set<Feature> get granted;
}

/// The source used while the app is free. Swapped for a Play Billing backed
/// source when gates are switched on.
final class AlwaysUnlockedSource implements EntitlementSource {
  const AlwaysUnlockedSource();

  /// Built once and shared. Gate checks run on every rebuild of a gated
  /// widget, so this getter must not allocate. Unmodifiable because a shared
  /// set that a caller can add to is a bug waiting to be written.
  static final Set<Feature> _all = Set.unmodifiable(Feature.values.toSet());

  @override
  Set<Feature> get granted => _all;
}

final class GrantedSetSource implements EntitlementSource {
  const GrantedSetSource(this.granted);

  @override
  final Set<Feature> granted;
}

final class Entitlements {
  const Entitlements({required this.source, required this.isFoundingUser});

  final EntitlementSource source;

  /// Set at first run before the early-access cutoff. Founding users retain
  /// full access permanently — a paywall that removes features people already
  /// use is a betrayal; one that grandfathers them is a gift.
  final bool isFoundingUser;

  bool has(Feature feature) =>
      isFoundingUser || source.granted.contains(feature);
}
