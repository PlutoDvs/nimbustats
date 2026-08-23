import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

CategoryObservation obs(String category, int daysAgo, {String? merchant}) =>
    CategoryObservation(
      categoryId: category,
      occurredAt: DateTime.utc(2026, 8, 21).subtract(Duration(days: daysAgo)),
      merchant: merchant,
    );

void main() {
  final now = DateTime.utc(2026, 8, 21, 12);

  test('empty history predicts nothing rather than throwing', () {
    const predictor = MruFrequencyCategoryPredictor([]);
    expect(predictor.predict(at: now), isEmpty);
  });

  test('a limit of zero returns nothing rather than everything', () {
    const predictor = MruFrequencyCategoryPredictor([]);
    expect(predictor.predict(at: now, limit: 0), isEmpty);
  });

  test('a merchant seen before wins outright', () {
    // This is the whole point: the second coffee at the same cafe should not
    // require thinking about categories at all.
    final predictor = MruFrequencyCategoryPredictor([
      obs('groceries', 0),
      obs('groceries', 1),
      obs('groceries', 2),
      obs('coffee', 30, merchant: 'Cafe Naderi'),
    ]);
    expect(predictor.predict(merchant: 'Cafe Naderi', at: now).first, 'coffee');
  });

  test('merchant matching ignores case and surrounding whitespace', () {
    final predictor = MruFrequencyCategoryPredictor([
      obs('coffee', 5, merchant: 'Cafe Naderi'),
    ]);
    expect(
      predictor.predict(merchant: '  cafe naderi ', at: now).first,
      'coffee',
    );
  });

  test('a blank merchant is treated as no merchant, not as a match', () {
    // Otherwise every observation with a null merchant would "match" an empty
    // string and every category would get the near-certain weight.
    final predictor = MruFrequencyCategoryPredictor([
      obs('groceries', 0),
      obs('coffee', 40),
    ]);
    expect(predictor.predict(merchant: '   ', at: now).first, 'groceries');
  });

  test('recent beats frequent when there is no merchant', () {
    // Twelve old groceries against two recent transport entries: what someone
    // did yesterday is a better guess for today than what they did in spring.
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 0; i < 12; i++) obs('groceries', 120 + i),
      obs('transport', 0),
      obs('transport', 1),
    ]);
    expect(predictor.predict(at: now).first, 'transport');
  });

  test('frequency breaks a recency tie', () {
    final predictor = MruFrequencyCategoryPredictor([
      obs('a', 1),
      obs('b', 1),
      obs('b', 2),
    ]);
    expect(predictor.predict(at: now).first, 'b');
  });

  test('ranking is deterministic when scores are identical', () {
    // Chips that reshuffle between rebuilds are worse than chips in a boring
    // order: muscle memory is the feature.
    final predictor = MruFrequencyCategoryPredictor([
      obs('zebra', 1),
      obs('apple', 1),
    ]);
    expect(predictor.predict(at: now), ['apple', 'zebra']);
    expect(predictor.predict(at: now), ['apple', 'zebra']);
  });

  test('respects the limit and never repeats a category', () {
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 0; i < 20; i++) obs('c${i % 6}', i),
    ]);
    final result = predictor.predict(at: now, limit: 4);
    expect(result, hasLength(4));
    expect(result.toSet(), hasLength(4));
  });

  test('a future-dated transaction is not scored as ancient history', () {
    // Someone logging tomorrow's rent should still see rent ranked. A signed
    // day difference would make it negative and the recency term explode.
    final predictor = MruFrequencyCategoryPredictor([
      CategoryObservation(
        categoryId: 'rent',
        occurredAt: DateTime.utc(2026, 8, 22, 12),
      ),
      obs('coffee', 40),
    ]);
    expect(predictor.predict(at: now).first, 'rent');
  });

  test('time of day nudges but does not dominate', () {
    // Coffee at 9am on eight mornings against one grocery run last night.
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 1; i <= 8; i++)
        CategoryObservation(
          categoryId: 'coffee',
          occurredAt: DateTime.utc(2026, 8, 21 - i, 9),
        ),
      CategoryObservation(
        categoryId: 'groceries',
        occurredAt: DateTime.utc(2026, 8, 20, 21),
      ),
    ]);
    expect(predictor.predict(at: DateTime.utc(2026, 8, 21, 9)).first, 'coffee');
  });
}
