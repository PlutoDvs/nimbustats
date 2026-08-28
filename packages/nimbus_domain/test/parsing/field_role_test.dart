import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('FieldRole', () {
    test('every role name is a valid regex group name', () {
      // role.name is used verbatim as (?<name>...), so a value with an
      // underscore or digit would produce a regex that does not compile.
      for (final role in FieldRole.values) {
        expect(role.name, matches(RegExp(r'^[A-Za-z]+$')),
            reason: '${role.name} cannot be a named capture group');
      }
    });
  });

  group('RoleAssignment', () {
    test('single() covers exactly one token', () {
      const a = RoleAssignment.single(3, FieldRole.amount);
      expect(a.startIndex, 3);
      expect(a.endIndex, 3);
    });

    test('a range covers several tokens, for a two-word merchant', () {
      const a =
          RoleAssignment(startIndex: 8, endIndex: 10, role: FieldRole.merchant);
      expect(a.endIndex - a.startIndex, 2);
    });
  });

  group('FieldMap', () {
    test('the group name for a role is the role name', () {
      final map = FieldMap.of([FieldRole.amount]);
      expect(map.groupFor(FieldRole.amount), 'amount');
    });

    test('has() reports only the roles that were assigned', () {
      final map = FieldMap.of([FieldRole.amount, FieldRole.date]);
      expect(map.has(FieldRole.amount), isTrue);
      expect(map.has(FieldRole.merchant), isFalse);
    });

    test('groupFor throws for a role the template does not define', () {
      // Callers must ask has() first. Returning null here would invite the
      // caller to pass null into namedGroup and get an ArgumentError from
      // deep inside the regex engine instead.
      final map = FieldMap.of([FieldRole.amount]);
      expect(() => map.groupFor(FieldRole.merchant), throwsArgumentError);
    });

    test('JSON round-trips', () {
      final map = FieldMap.of([FieldRole.amount, FieldRole.merchant]);
      expect(FieldMap.fromJson(map.toJson()), map);
    });

    test('fromJson rejects an unknown role rather than dropping it', () {
      // A silently dropped role means a template that quietly stops
      // capturing the amount. Loud beats subtle.
      expect(() => FieldMap.fromJson({'amount': 'amount', 'wat': 'wat'}),
          throwsFormatException);
    });

    test('two maps with the same roles are equal', () {
      expect(FieldMap.of([FieldRole.amount, FieldRole.date]),
          FieldMap.of([FieldRole.date, FieldRole.amount]));
    });
  });
}
