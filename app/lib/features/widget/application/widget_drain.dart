import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../notifications/data/outside_channel.dart';
import '../../trackers/data/tracker_repository.dart';
import '../../transactions/data/transaction_draft.dart';
import '../../transactions/data/transaction_repository.dart';

/// The largest amount a buffer line may carry. It is the dialog's own bound
/// (`AmountParser.MAX_MINOR`), checked again here because the buffer is a
/// trust boundary.
const maxAmountMinor = 999999999999999;

/// What one pass over the buffer decided (spec §2.3 step 2). [failed] counts
/// lines left for the next drain after an unexpected error.
typedef DrainOutcome = ({
  List<String> ackIds,
  List<RejectedLine> rejected,
  int failed,
});

/// Writes widget buffer lines through the app's one write path, each
/// exactly once (spec §2.2, §2.3).
///
/// A line's id is its row's id, so a repeated drain writes nothing new and a
/// deleted row stays deleted. Each line is settled one of three ways:
/// - **acked**: written, or written before. A boolean already done that day
///   is acked too, because that is the repository's rule.
/// - **rejected, with a reason**:
///   - a malformed line, or one with an unknown version or kind;
///   - an amount out of range;
///   - a tracker gone, archived, or timed.
/// - **left in place**: anything unexpected, reported under `widget drain`.
///   It is retried by the next drain.
///
/// A category deleted since the snapshot is not a rejection. The expense
/// is filed as Uncategorized, because the amount is what matters.
final class WidgetDrain {
  WidgetDrain({
    required this._db,
    required this._transactions,
    required this._trackers,
  });

  final AppDatabase _db;
  final TransactionRepository _transactions;
  final TrackerRepository _trackers;

  Future<DrainOutcome> apply(List<String> lines) async {
    final ackIds = <String>[];
    final rejected = <RejectedLine>[];
    var failed = 0;
    for (final raw in lines) {
      final _Line line;
      try {
        line = _Line.parse(raw);
      } on FormatException catch (error) {
        rejected.add((line: raw, reason: error.message));
        continue;
      }
      try {
        final reason = await switch (line) {
          _Expense() => _expense(line),
          _Tap() => _tap(line),
        };
        if (reason == null) {
          ackIds.add(line.id);
        } else {
          rejected.add((line: raw, reason: reason));
        }
      } on Object catch (error, stack) {
        failed++;
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'widget drain',
          context: ErrorDescription(
              'while writing buffer line ${line.id}; it stays for the next drain'),
        ));
      }
    }
    return (ackIds: ackIds, rejected: rejected, failed: failed);
  }

  Future<String?> _expense(_Expense line) async {
    final chosen = line.categoryId;
    final category = chosen == null ? null : await _db.categoriesDao.byId(chosen);
    await _transactions.add(
      TransactionDraft(
        amount: Money(line.amountMinor),
        direction: TxDirection.expense,
        categoryId: category != null && category.deletedAt == null
            ? category.id
            : SystemCategoryIds.uncategorized,
        occurredAtUtc: line.at,
        source: TxSource.widget,
      ),
      id: line.id,
    );
    return null;
  }

  Future<String?> _tap(_Tap line) async {
    final tracker = await _db.trackersDao.byId(line.trackerId); // live only
    if (tracker == null) return 'tracker gone';
    if (tracker.archived) return 'tracker archived';
    if (tracker.type == TrackerType.duration) return 'duration tracker';
    final result = await _trackers.logEntry(tracker.id, at: line.at, id: line.id);
    return switch (result) {
      EntryLogged() || AlreadyLogged() || AlreadyDoneToday() => null,
    };
  }
}

/// One buffer line (spec §2.1).
sealed class _Line {
  const _Line(this.id, this.at);

  final String id;

  /// The tap time, so a late drain files the tap when it happened.
  final DateTime at;

  /// Throws [FormatException] whose message is the rejection's reason.
  static _Line parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('malformed line');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('malformed line');
    }
    if (decoded['v'] != 1) {
      throw FormatException('unknown line version ${decoded['v']}');
    }
    final id = decoded['id'];
    final atUtc = decoded['atUtc'];
    // Past DateTime's range the constructor below would throw, not reject.
    if (id is! String ||
        id.isEmpty ||
        atUtc is! int ||
        atUtc.abs() > 8640000000000000) {
      throw const FormatException('malformed line');
    }
    final at = DateTime.fromMillisecondsSinceEpoch(atUtc, isUtc: true);
    switch (decoded['kind']) {
      case 'expense':
        final amount = decoded['amountMinor'];
        final category = decoded['categoryId'];
        if (amount is! int || amount < 1 || amount > maxAmountMinor) {
          throw FormatException('amount out of range: $amount');
        }
        if (category != null && category is! String) {
          throw const FormatException('malformed line');
        }
        return _Expense(id, at, amount, category as String?);
      case 'tracker':
        final trackerId = decoded['trackerId'];
        if (trackerId is! String) throw const FormatException('malformed line');
        return _Tap(id, at, trackerId);
      default:
        throw FormatException('unknown line kind ${decoded['kind']}');
    }
  }
}

final class _Expense extends _Line {
  const _Expense(super.id, super.at, this.amountMinor, this.categoryId);

  final int amountMinor;
  final String? categoryId;
}

final class _Tap extends _Line {
  const _Tap(super.id, super.at, this.trackerId);

  final String trackerId;
}
