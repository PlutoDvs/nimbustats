import 'package:meta/meta.dart';

/// How a set of tag subtrees narrows a query.
///
/// The three kinds mean genuinely different things and a round trip that
/// changes the kind changes the answer, so the kind is part of the JSON and an
/// unknown one throws rather than defaulting.
@immutable
sealed class TagFilter {
  const TagFilter();

  factory TagFilter.fromJson(Map<String, Object?> json) {
    final paths = _pathsOf(json['paths']);
    return switch (json['kind']) {
      'all' => TagsAll(paths),
      'any' => TagsAny(paths),
      'none' => TagsNone(paths),
      final other => throw FormatException('unknown tag filter kind "$other"'),
    };
  }

  /// Materialized paths, not ids: a tag filter always means "this subtree".
  List<String> get subtreePaths;

  Map<String, Object?> toJson();

  static List<String> _pathsOf(Object? value) => switch (value) {
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a path list, got "$value"'),
      };

  static void _requireNonEmpty(List<String> paths) {
    if (paths.isEmpty) {
      throw ArgumentError('a tag filter needs at least one subtree path');
    }
  }

  static bool _samePaths(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The transaction carries **every** one of these subtrees.
@immutable
final class TagsAll extends TagFilter {
  TagsAll(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'all', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsAll && TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('all', Object.hashAll(subtreePaths));
}

/// The transaction carries **at least one** of these subtrees.
@immutable
final class TagsAny extends TagFilter {
  TagsAny(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'any', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsAny && TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('any', Object.hashAll(subtreePaths));
}

/// The transaction carries **none** of these subtrees.
@immutable
final class TagsNone extends TagFilter {
  TagsNone(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'none', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsNone &&
      TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('none', Object.hashAll(subtreePaths));
}
