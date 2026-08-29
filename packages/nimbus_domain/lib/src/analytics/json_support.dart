/// Shared JSON-reading helpers for the analytics value types.
///
/// Lives in its own file so `query_spec.dart` and `query_filters.dart` do not
/// have to import each other: they are mutually referential at the type level
/// already, and a mutual import for one static helper is the kind of thing
/// that quietly grows into a cycle nobody can unpick.
library;

/// Reads a required nested object, throwing [FormatException] when it is
/// absent or the wrong shape.
///
/// A bare `!` would throw a TypeError here, which is an Error rather than an
/// Exception -- a caller that reasonably catches Exception around a stored
/// spec would not catch it, and one corrupt row would take the app down
/// instead of being reported.
Map<String, Object?> jsonMapOf(Object? value, String field) => value is Map
    ? value.cast<String, Object?>()
    : throw FormatException('expected an object for "$field", got "$value"');
