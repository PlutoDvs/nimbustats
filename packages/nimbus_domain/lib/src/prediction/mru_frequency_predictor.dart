import 'category_observation.dart';
import 'category_predictor.dart';

/// Most-recently-used plus most-frequent, with a merchant short-circuit.
///
/// Phase 2 replaces this with merchant-rule-backed prediction behind the same
/// interface, which is why [CategoryPredictor] is an interface at all rather
/// than a helper function.
final class MruFrequencyCategoryPredictor implements CategoryPredictor {
  const MruFrequencyCategoryPredictor(this._history);

  final List<CategoryObservation> _history;

  // Weights are deliberately far apart rather than tuned. A merchant match is
  // near-certain knowledge; recency is a good guess; frequency is a weak
  // prior; hour-of-day is a nudge. Tuning them against real usage is Phase 2's
  // job, once there is real usage to tune against -- tuning now would only fit
  // them to imagined behaviour.
  static const _merchantWeight = 100.0;
  static const _recencyWeight = 10.0;
  static const _frequencyWeight = 1.0;
  static const _hourWeight = 2.0;

  @override
  List<String> predict({String? merchant, DateTime? at, int limit = 4}) {
    if (_history.isEmpty || limit <= 0) return const [];
    final now = at ?? DateTime.now();
    final needle = _normalize(merchant);
    final scores = <String, double>{};

    for (final observation in _history) {
      var score = _frequencyWeight;

      // Absolute, so a transaction dated tomorrow -- rent paid ahead, say --
      // scores as recent rather than as a negative that inverts the term.
      final days = now.difference(observation.occurredAt).inDays.abs();
      // Hyperbolic rather than exponential: yesterday and last week should
      // still be comparable, while last spring should not be.
      score += _recencyWeight / (1 + days);

      if (needle != null && _normalize(observation.merchant) == needle) {
        score += _merchantWeight;
      }

      final hourGap = (observation.occurredAt.hour - now.hour).abs();
      if (hourGap <= 2) score += _hourWeight * (3 - hourGap) / 3;

      scores.update(
        observation.categoryId,
        (value) => value + score,
        ifAbsent: () => score,
      );
    }

    final ranked = scores.keys.toList()
      ..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        // Alphabetical tiebreak so chip order never reshuffles between
        // rebuilds. Muscle memory is the feature.
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    return ranked.take(limit).toList();
  }

  /// Folds case and trims, and treats a blank string as absent.
  ///
  /// The blank case matters: without it an empty merchant would compare equal
  /// to every observation that has no merchant, and the near-certain weight
  /// would land on all of them at once.
  static String? _normalize(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
