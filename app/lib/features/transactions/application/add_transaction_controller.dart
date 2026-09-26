import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import '../data/transaction_draft.dart';

/// Everything the add screen has collected so far.
///
/// The amount is held as *text*, not as [Money]. Parsing happens once, at
/// save, so an intermediate state like `1.` is a thing the user is typing
/// rather than a value the model has to represent.
final class AddTransactionState {
  const AddTransactionState({
    required this.date,
    this.amountText = '',
    this.direction = TxDirection.expense,
    this.categoryId,
    this.tagIds = const {},
    this.paymentMethodId,
    this.merchant,
    this.note,
    this.amountError = false,
  });

  final String amountText;
  final TxDirection direction;

  /// Null means the user has not chosen one. It becomes the reserved
  /// Uncategorized row at save, never a null column.
  final String? categoryId;

  final Set<String> tagIds;
  final String? paymentMethodId;
  final String? merchant;
  final String? note;

  /// Local wall-clock time of the transaction. Defaults to now, which is what
  /// makes "today" free rather than a field to fill in.
  final DateTime date;

  final bool amountError;

  AddTransactionState copyWith({
    String? amountText,
    TxDirection? direction,
    String? categoryId,
    Set<String>? tagIds,
    String? paymentMethodId,
    String? merchant,
    String? note,
    DateTime? date,
    bool? amountError,
  }) =>
      AddTransactionState(
        amountText: amountText ?? this.amountText,
        direction: direction ?? this.direction,
        categoryId: categoryId ?? this.categoryId,
        tagIds: tagIds ?? this.tagIds,
        paymentMethodId: paymentMethodId ?? this.paymentMethodId,
        merchant: merchant ?? this.merchant,
        note: note ?? this.note,
        date: date ?? this.date,
        amountError: amountError ?? this.amountError,
      );
}

/// Holds the add form and turns it into a [TransactionDraft].
class AddTransactionController extends Notifier<AddTransactionState> {
  @override
  AddTransactionState build() => AddTransactionState(date: DateTime.now());

  void setAmountText(String value) =>
      state = state.copyWith(amountText: value, amountError: false);

  void selectCategory(String id) => state = state.copyWith(categoryId: id);

  void setDirection(TxDirection direction) =>
      state = state.copyWith(direction: direction);

  void toggleTag(String id) {
    final next = {...state.tagIds};
    if (!next.remove(id)) next.add(id);
    state = state.copyWith(tagIds: next);
  }

  void setTags(Set<String> ids) => state = state.copyWith(tagIds: ids);

  void setPaymentMethod(String? id) =>
      state = AddTransactionState(
        amountText: state.amountText,
        direction: state.direction,
        categoryId: state.categoryId,
        tagIds: state.tagIds,
        // Assigned directly rather than through copyWith, because null here
        // means "none" and copyWith cannot tell that from "unchanged".
        paymentMethodId: id,
        merchant: state.merchant,
        note: state.note,
        date: state.date,
      );

  void setMerchant(String? value) => state = state.copyWith(merchant: value);

  void setNote(String? value) => state = state.copyWith(note: value);

  /// Replaces the date, keeping the time of day already captured.
  void setDate(DateTime day) => state = state.copyWith(
        date: DateTime(
          day.year,
          day.month,
          day.day,
          state.date.hour,
          state.date.minute,
        ),
      );

  /// The draft to save, or null when the amount is missing or malformed.
  ///
  /// Sets [AddTransactionState.amountError] as a side effect so the field can
  /// say what is wrong. Amount is the only thing that can fail: every other
  /// field is optional by design, and a category that was never chosen becomes
  /// the Uncategorized row rather than blocking the save.
  TransactionDraft? validate() {
    final amount = ref.read(moneyFormatterProvider).parse(state.amountText);
    if (amount == null || amount.minorUnits == 0) {
      state = state.copyWith(amountError: true);
      return null;
    }

    return TransactionDraft(
      amount: amount.isNegative ? Money(-amount.minorUnits) : amount,
      direction: state.direction,
      categoryId: state.categoryId ?? SystemCategoryIds.uncategorized,
      occurredAtUtc: state.date.toUtc(),
      paymentMethodId: state.paymentMethodId,
      merchant: _blankToNull(state.merchant),
      note: _blankToNull(state.note),
      tagIds: state.tagIds.toList(),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// Auto-disposed, so the form lives exactly as long as the add screen does.
///
/// A plain NotifierProvider is kept alive for the whole session, and a draft
/// that outlived its screen opened the next add with the last category chosen,
/// the last amount held behind an empty-looking field, and the timestamp of
/// the first time the form was ever built.
final addTransactionControllerProvider =
    NotifierProvider.autoDispose<AddTransactionController, AddTransactionState>(
  AddTransactionController.new,
);
