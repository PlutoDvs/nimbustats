import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Everything needed to record one transaction, and nothing that the database
/// decides for itself.
///
/// Deliberately absent: `id`, `createdAt`, `updatedAt`, `currencyCode`, and
/// `localDateKey`. Those are derived by [TransactionRepository] from the active
/// settings and the clock, so no caller can get them subtly wrong -- and
/// Phase 2's captures and Phase 6's widget build the same draft type rather
/// than each computing a date key of their own.
///
/// [amount] is [Money], never a double. A Toman amount large enough to matter
/// loses precision the moment it becomes a floating-point number.
final class TransactionDraft {
  TransactionDraft({
    required this.amount,
    required this.direction,
    required this.categoryId,
    required this.occurredAtUtc,
    this.paymentMethodId,
    this.merchant,
    this.note,
    this.tagIds = const [],
    this.necessity,
    this.satisfaction,
    this.source = TxSource.manual,
    this.isConfirmed = true,
    this.captureId,
  }) : assert(
          occurredAtUtc.isUtc,
          'occurredAtUtc must be UTC. The local date key is derived from it, '
          'so a local DateTime here silently files spending under the wrong '
          'day for anyone not on UTC.',
        );

  /// A draft for spending whose category is not known yet.
  ///
  /// Points at the reserved system row rather than leaving `categoryId` null.
  /// Every chart in this app groups by category, so a null would either be
  /// dropped from the totals or need special-casing in each one.
  factory TransactionDraft.uncategorized({
    required Money amount,
    required TxDirection direction,
    required DateTime occurredAtUtc,
    String? paymentMethodId,
    String? merchant,
    String? note,
    List<String> tagIds = const [],
    TxSource source = TxSource.manual,
    bool isConfirmed = true,
    String? captureId,
  }) =>
      TransactionDraft(
        amount: amount,
        direction: direction,
        categoryId: SystemCategoryIds.uncategorized,
        occurredAtUtc: occurredAtUtc,
        paymentMethodId: paymentMethodId,
        merchant: merchant,
        note: note,
        tagIds: tagIds,
        source: source,
        isConfirmed: isConfirmed,
        captureId: captureId,
      );

  final Money amount;
  final TxDirection direction;
  final String categoryId;
  final DateTime occurredAtUtc;
  final String? paymentMethodId;
  final String? merchant;
  final String? note;
  final List<String> tagIds;

  /// Set on the edit screen only. Asking for them in the add flow is what
  /// turns a three-tap capture into a form nobody fills in twice.
  final Necessity? necessity;
  final Satisfaction? satisfaction;

  final TxSource source;
  final bool isConfirmed;

  /// Set by Phase 2 when this draft came from a parsed message, so a captured
  /// transaction can be traced back to the text it was read from.
  final String? captureId;

  TransactionDraft copyWith({
    Money? amount,
    TxDirection? direction,
    String? categoryId,
    DateTime? occurredAtUtc,
    String? paymentMethodId,
    String? merchant,
    String? note,
    List<String>? tagIds,
    Necessity? necessity,
    Satisfaction? satisfaction,
    TxSource? source,
    bool? isConfirmed,
    String? captureId,
  }) =>
      TransactionDraft(
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
        categoryId: categoryId ?? this.categoryId,
        occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
        paymentMethodId: paymentMethodId ?? this.paymentMethodId,
        merchant: merchant ?? this.merchant,
        note: note ?? this.note,
        tagIds: tagIds ?? this.tagIds,
        necessity: necessity ?? this.necessity,
        satisfaction: satisfaction ?? this.satisfaction,
        source: source ?? this.source,
        isConfirmed: isConfirmed ?? this.isConfirmed,
        captureId: captureId ?? this.captureId,
      );
}
