/// Path helpers shared by the category and tag trees.
///
/// The path format is `/rootId/childId/` -- leading and trailing slashes are
/// both load-bearing. The trailing slash is what keeps `/food/` from matching
/// `/foodstuff/` on a prefix comparison.
abstract final class MaterializedPath {
  static String childPath(String? parentPath, String id) =>
      '${parentPath ?? '/'}$id/';

  static int depthOf(String path) =>
      path.split('/').where((s) => s.isNotEmpty).length - 1;

  static bool isDescendant({
    required String path,
    required String ancestorPath,
  }) =>
      path.startsWith(ancestorPath) && path != ancestorPath;

  /// Exclusive upper bound of the subtree rooted at [path], for use as
  /// `path >= p AND path < subtreeUpperBound(p)`.
  ///
  /// Incrementing the final character gives the first string that sorts after
  /// every descendant, so the pair is exactly the set of strings prefixed by
  /// [path]. This is preferred over `LIKE 'p%'` for two reasons: SQLite cannot
  /// use an index for LIKE unless the column is declared NOCASE, and `_` and
  /// `%` inside an id would act as wildcards.
  static String subtreeUpperBound(String path) {
    final last = path.codeUnitAt(path.length - 1);
    return '${path.substring(0, path.length - 1)}'
        '${String.fromCharCode(last + 1)}';
  }

  /// Rewrites [path] so the segment rooted at [oldAncestorPath] now sits under
  /// [newAncestorPath].
  static String reparent({
    required String path,
    required String oldAncestorPath,
    required String newAncestorPath,
  }) =>
      newAncestorPath + path.substring(oldAncestorPath.length);
}
