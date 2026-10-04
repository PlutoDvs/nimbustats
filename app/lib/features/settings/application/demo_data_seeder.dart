import 'dart:math';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../tags/data/tag_repository.dart';
import '../../transactions/data/transaction_draft.dart';
import '../../transactions/data/transaction_repository.dart';

/// Debug-only: a history shaped like real use, to measure the app against.
///
/// Shape matters as much as size. Rows with no tags, no ratings and every
/// category used equally leave the cross-tab, the reflection matrix and every
/// tag filter measuring empty data, and an even spread hides the long tail
/// that real category use has. So: two years, a few heavy categories and many
/// light ones, two or three tags on every row (some a tag with its own
/// parent, which rollup must count once), ratings on most spending, and a few
/// unconfirmed captures for the confirmed-only switch to filter out.
///
/// Deterministic for a given [Random] seed, so a measurement repeated later is
/// taken against the same data. Every row goes through
/// [TransactionRepository.add], the only insert path.
final class DemoDataSeeder {
  DemoDataSeeder({
    required this._transactions,
    required this._tags,
    required List<String> categoryIds,
    required this._paymentMethodIds,
    required this._nowUtc,
    Random? random,
  })  : _random = random ?? Random(_defaultSeed),
        _categoryIds = [...categoryIds] {
    if (categoryIds.isEmpty) {
      throw ArgumentError.value(
          categoryIds, 'categoryIds', 'no category to file rows under');
    }
    // Shuffled before ranking, so which category is heavy does not simply
    // follow the order of the tree.
    _categoryIds.shuffle(_random);
  }

  static const rowCount = 5000;
  static const span = Duration(days: 730);

  static const _defaultSeed = 20261004;

  /// Parents with their children. Two parents have children, so rows can
  /// carry a tag and its parent.
  static const _tagTree = <String, List<String>>{
    'work': [],
    'family': [],
    'travel': ['flights', 'hotels'],
    'health': [],
    'gifts': [],
    'subscriptions': [],
    'weekend': [],
    'home': ['repairs', 'furniture'],
  };

  /// Relative likelihood of each local hour: quiet nights, a morning bump,
  /// and lunch and evening peaks.
  static const _hourWeights = <double>[
    0.1, 0.05, 0.05, 0.05, 0.05, 0.1, 0.3, 0.8, 1.5, 1.2, 1, 1, //
    2.5, 3, 2, 1, 1, 1.5, 2.5, 3, 2.5, 1.5, 0.8, 0.3,
  ];

  final TransactionRepository _transactions;
  final TagRepository _tags;
  final List<String> _categoryIds;
  final List<String> _paymentMethodIds;
  final DateTime _nowUtc;
  final Random _random;

  Future<void> seed({int count = rowCount}) async {
    final tags = await _demoTags();
    final children = [for (final tag in tags) if (tag.parentId != null) tag];
    final categoryWeights = _zipf(_categoryIds.length);
    final tagWeights = _zipf(tags.length);

    final nowLocal = _nowUtc.toLocal();
    for (var i = 0; i < count; i++) {
      final income = _random.nextInt(11) == 0;
      final rated = !income && _random.nextDouble() < 0.7;
      final unconfirmed = _random.nextDouble() < 0.05;
      await _transactions.add(TransactionDraft(
        amount: income ? _amount(5000000, 20000000) : _amount(5000, 2000000),
        direction: income ? TxDirection.income : TxDirection.expense,
        categoryId: _categoryIds[_pick(categoryWeights)],
        occurredAtUtc: _occurredAt(nowLocal),
        paymentMethodId: _paymentMethodIds.isNotEmpty &&
                _random.nextDouble() < 0.8
            ? _paymentMethodIds[_random.nextInt(_paymentMethodIds.length)]
            : null,
        merchant: _random.nextInt(3) == 0
            ? 'Merchant ${_random.nextInt(40)}'
            : null,
        tagIds: _tagIdsFor(tags, children, tagWeights),
        necessity: rated
            ? Necessity.values[_random.nextInt(Necessity.values.length)]
            : null,
        satisfaction: rated
            ? Satisfaction.values[_random.nextInt(Satisfaction.values.length)]
            : null,
        // An unconfirmed row is what a capture leaves for review.
        source: unconfirmed ? TxSource.sms : TxSource.manual,
        isConfirmed: !unconfirmed,
      ));
    }
  }

  Future<List<Tag>> _demoTags() async {
    final tags = <Tag>[];
    for (final MapEntry(key: name, value: childNames) in _tagTree.entries) {
      final parent = await _tags.findOrCreate(name);
      tags.add(parent);
      for (final child in childNames) {
        tags.add(await _tags.findOrCreate(child, parentId: parent.id));
      }
    }
    return tags;
  }

  List<String> _tagIdsFor(
      List<Tag> tags, List<Tag> children, List<double> weights) {
    final wanted = 2 + _random.nextInt(2);
    final picked = <String>{};
    if (_random.nextDouble() < 0.1) {
      final child = children[_random.nextInt(children.length)];
      picked
        ..add(child.id)
        ..add(child.parentId!);
    }
    while (picked.length < wanted) {
      picked.add(tags[_pick(weights)].id);
    }
    return picked.toList();
  }

  /// A local time on one of the last [span]'s days, at a weighted hour, never
  /// later than now.
  DateTime _occurredAt(DateTime nowLocal) {
    final daysBack = _random.nextInt(span.inDays);
    var at = DateTime(nowLocal.year, nowLocal.month, nowLocal.day - daysBack,
        _pick(_hourWeights), _random.nextInt(60));
    if (at.isAfter(nowLocal)) at = at.subtract(const Duration(days: 1));
    return at.toUtc();
  }

  /// Log-uniform between [low] and [high], so small amounts are common and
  /// large ones rare, rounded to 500 as prices are.
  Money _amount(int low, int high) {
    final logAmount =
        log(low) + _random.nextDouble() * (log(high) - log(low));
    return Money((exp(logAmount) / 500).round() * 500);
  }

  /// Weights 1, 1/2, 1/3, …: a few heavy items and a long tail.
  static List<double> _zipf(int n) => [for (var r = 1; r <= n; r++) 1 / r];

  int _pick(List<double> weights) {
    var remaining = _random.nextDouble() * weights.reduce((a, b) => a + b);
    for (var i = 0; i < weights.length; i++) {
      remaining -= weights[i];
      if (remaining < 0) return i;
    }
    return weights.length - 1;
  }
}
