/// How a saved view is drawn.
///
/// Fixed by where the view was pinned from -- each tab and each patterns
/// chart pins its own kind -- so a spec is never paired with a chart that
/// cannot draw it. Stored by [name].
enum SavedViewChart {
  breakdown,
  trend,
  crossTab,
  hourOfDay,
  dayOfWeek,
  reflection;

  /// Throws [FormatException] on an unknown name rather than guessing: a
  /// guessed chart would draw another answer under the user's own name for
  /// this one.
  static SavedViewChart parse(String raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown saved-view chart "$raw"');
  }
}
