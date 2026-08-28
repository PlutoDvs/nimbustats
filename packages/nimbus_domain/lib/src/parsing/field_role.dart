import 'package:meta/meta.dart';

/// What a tapped run of a message means.
///
/// The enum name is used verbatim as a regex named capture group, so every
/// value must remain a bare sequence of letters.
enum FieldRole { amount, merchant, date, card, balance }

/// A contiguous run of tokens the user assigned to one role.
///
/// This is a range rather than a single index because a merchant is routinely
/// two words and a card number tokenizes as number / word / number.
@immutable
final class RoleAssignment {
  const RoleAssignment({
    required this.startIndex,
    required this.endIndex,
    required this.role,
  });

  const RoleAssignment.single(int index, this.role)
      : startIndex = index,
        endIndex = index;

  final int startIndex;
  final int endIndex;
  final FieldRole role;

  @override
  bool operator ==(Object other) =>
      other is RoleAssignment &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex &&
      other.role == role;

  @override
  int get hashCode => Object.hash(startIndex, endIndex, role);

  @override
  String toString() => 'RoleAssignment(${role.name}, $startIndex..$endIndex)';
}

/// Which named group carries which role, as persisted in the
/// `message_templates.field_map` column.
///
/// The matcher consults this instead of probing the compiled regex, because
/// `RegExpMatch.namedGroup` throws for a group the pattern does not define —
/// which is every template for a bank that does not print a merchant.
@immutable
final class FieldMap {
  const FieldMap._(this._roles);

  factory FieldMap.of(Iterable<FieldRole> roles) =>
      FieldMap._(Set.unmodifiable(roles));

  factory FieldMap.fromJson(Map<String, Object?> json) {
    final roles = <FieldRole>{};
    for (final key in json.keys) {
      FieldRole? found;
      for (final role in FieldRole.values) {
        if (role.name == key) found = role;
      }
      if (found == null) {
        throw FormatException('unknown field role "$key"');
      }
      roles.add(found);
    }
    return FieldMap.of(roles);
  }

  final Set<FieldRole> _roles;

  Set<FieldRole> get roles => _roles;

  bool has(FieldRole role) => _roles.contains(role);

  /// The regex group name carrying [role].
  ///
  /// Throws if the template does not define it — callers ask [has] first.
  String groupFor(FieldRole role) {
    if (!has(role)) {
      throw ArgumentError.value(
          role.name, 'role', 'this template defines no such group');
    }
    return role.name;
  }

  Map<String, Object?> toJson() =>
      <String, Object?>{for (final role in _roles) role.name: role.name};

  @override
  bool operator ==(Object other) =>
      other is FieldMap &&
      other._roles.length == _roles.length &&
      other._roles.containsAll(_roles);

  @override
  int get hashCode => Object.hashAllUnordered(_roles.map((r) => r.name));

  @override
  String toString() =>
      'FieldMap(${(_roles.map((r) => r.name).toList()..sort()).join(', ')})';
}
