import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// The write path for payment methods.
///
/// A payment method answers "where did this go out from" and nothing more.
/// There are no balances and no reconciliation anywhere in this app, by
/// design, so nothing here ever has to be made to add up.
final class PaymentMethodRepository {
  const PaymentMethodRepository(this._dao);

  final PaymentMethodsDao _dao;

  /// Every live method, archived included: the manager's view.
  Stream<List<PaymentMethod>> watchAll() => _dao.watchAll();

  /// What the add screen offers. Archived methods are excluded -- archiving is
  /// how a user retires a closed card without erasing the history it labels.
  Future<List<PaymentMethod>> pickable() =>
      _dao.allLive(includeArchived: false);

  /// Resolves a method for display, including archived and deleted ones.
  ///
  /// This is a label lookup, not a liveness check: a transaction paid from a
  /// card the user later removed must still render something. Liveness is what
  /// [watchAll] and [pickable] answer.
  Future<PaymentMethod?> byId(String id) => _dao.byId(id);

  Future<PaymentMethod> create({
    required String name,
    required PaymentMethodKind kind,
    String? last4,
    int color = 0xFF9E9E9E,
    String iconKey = 'card',
  }) async {
    final id = Ids.newId();
    await _dao.insertMethod(
      id: id,
      name: _validName(name),
      kind: kind,
      last4: _validLast4(last4),
      color: color,
      iconKey: iconKey,
    );
    return (await _dao.byId(id))!;
  }

  Future<void> update(
    String id, {
    String? name,
    PaymentMethodKind? kind,
    String? last4,
    int? color,
    String? iconKey,
  }) =>
      _dao.updateMethod(
        id,
        name: name == null ? null : _validName(name),
        kind: kind,
        last4: last4 == null ? null : _validLast4(last4),
        color: color,
        iconKey: iconKey,
      );

  Future<void> archive(String id) => _dao.setArchived(id, true);

  Future<void> unarchive(String id) => _dao.setArchived(id, false);

  /// Soft-deletes [id], returning it so an undo restores exactly this.
  ///
  /// Returns a list for the same shape as the category and tag repositories,
  /// whose deletes take subtrees. One screen pattern, one undo pattern.
  Future<List<String>> delete(String id) async {
    await _dao.softDelete(id);
    return [id];
  }

  Future<void> restore(List<String> ids) => _dao.restoreAll(ids);

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A payment method needs a name');
    }
    return trimmed;
  }

  /// Normalises Persian and Arabic-Indic digits, then insists on exactly four
  /// Latin ones.
  ///
  /// Normalising first because a user typing `۱۲۳۴` means 1234, and storing
  /// the Persian codepoints would leave the value unmatchable against an SMS
  /// capture in Phase 2.
  ///
  /// Anything longer is rejected outright rather than truncated. This app has
  /// no reason to hold a full card number, and the surest way to guarantee it
  /// never does is to refuse one at the door instead of quietly keeping the
  /// last four of it -- a caller passing sixteen digits has misunderstood, and
  /// silently accepting that is how the misunderstanding spreads.
  static String? _validLast4(String? last4) {
    if (last4 == null) return null;
    final normalised = Digits.toLatin(last4).trim();
    if (normalised.isEmpty) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(normalised)) {
      throw ArgumentError.value(
        last4,
        'last4',
        'Expected exactly four digits',
      );
    }
    return normalised;
  }
}
