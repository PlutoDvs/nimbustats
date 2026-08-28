import 'package:meta/meta.dart';

import 'direction_rule.dart';
import 'field_role.dart';

/// A learned message format, as persisted in `message_templates`.
///
/// Everything that can be wrong with a template is checked in the
/// constructor: an uncompilable regex, an invalid sender pattern, a
/// non-positive scale, or a field map claiming a group the regex does not
/// define. Each of those would otherwise surface as an exception in the
/// middle of ingesting a real message, which is the worst possible moment.
@immutable
final class MessageTemplate {
  MessageTemplate({
    required this.id,
    required this.name,
    required this.senderPattern,
    required this.regex,
    required this.fieldMap,
    required this.amountScale,
    required this.directionRule,
    required this.priority,
    required this.enabled,
    this.packageName,
    this.sampleBody,
  }) {
    if (amountScale < 1) {
      throw ArgumentError.value(
          amountScale, 'amountScale', 'must be a positive divisor');
    }
    try {
      _compiled = RegExp(regex);
      _sender = RegExp(senderPattern);
    } on FormatException catch (error) {
      throw FormatException(
          'template $id has an invalid pattern: ${error.message}');
    }
    for (final role in fieldMap.roles) {
      if (!regex.contains('(?<${role.name}>')) {
        throw ArgumentError.value(
            role.name,
            'fieldMap',
            'template $id declares this role but its regex defines no such '
                'group');
      }
    }
  }

  factory MessageTemplate.fromJson(Map<String, Object?> json) =>
      MessageTemplate(
        id: json['id']! as String,
        name: json['name']! as String,
        senderPattern: json['senderPattern']! as String,
        regex: json['regex']! as String,
        fieldMap:
            FieldMap.fromJson((json['fieldMap']! as Map).cast<String, Object?>()),
        amountScale: json['amountScale']! as int,
        directionRule: DirectionRule.fromJson(
            (json['directionRule']! as Map).cast<String, Object?>()),
        priority: json['priority']! as int,
        enabled: json['enabled']! as bool,
        packageName: json['packageName'] as String?,
        sampleBody: json['sampleBody'] as String?,
      );

  final String id;
  final String name;
  final String senderPattern;
  final String regex;
  final FieldMap fieldMap;

  /// Divisor applied to the parsed amount. Banks quote Rial, the app stores
  /// Toman, so an Iranian template carries 10.
  final int amountScale;
  final DirectionRule directionRule;

  /// Higher is tried first; `TemplateMatcher` breaks ties by ascending [id].
  final int priority;
  final bool enabled;
  final String? packageName;
  final String? sampleBody;

  late final RegExp _compiled;
  late final RegExp _sender;

  RegExp compiled() => _compiled;

  bool matchesSender(String sender) => _sender.hasMatch(sender);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'senderPattern': senderPattern,
        'regex': regex,
        'fieldMap': fieldMap.toJson(),
        'amountScale': amountScale,
        'directionRule': directionRule.toJson(),
        'priority': priority,
        'enabled': enabled,
        if (packageName != null) 'packageName': packageName,
        if (sampleBody != null) 'sampleBody': sampleBody,
      };

  @override
  bool operator ==(Object other) =>
      other is MessageTemplate &&
      other.id == id &&
      other.name == name &&
      other.senderPattern == senderPattern &&
      other.regex == regex &&
      other.fieldMap == fieldMap &&
      other.amountScale == amountScale &&
      other.directionRule == directionRule &&
      other.priority == priority &&
      other.enabled == enabled &&
      other.packageName == packageName &&
      other.sampleBody == sampleBody;

  @override
  int get hashCode => Object.hash(id, name, senderPattern, regex, fieldMap,
      amountScale, directionRule, priority, enabled, packageName, sampleBody);

  @override
  String toString() => 'MessageTemplate($id, $name, priority $priority)';
}
