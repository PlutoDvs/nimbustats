/// A node in the first-run category tree.
///
/// Names arrive already localized: this package has no access to ARB bundles
/// and must not gain one, so the app hands in a fully-resolved tree.
///
/// Ids are declared rather than generated. A stable `seed-food` id means a
/// merchant rule written in Phase 2 keeps pointing at the same category after
/// a reinstall, and it makes seeding idempotent by construction rather than by
/// comparing names.
final class SeedCategoryNode {
  const SeedCategoryNode({
    required this.id,
    required this.name,
    this.iconKey = 'tag',
    this.color = 0xFF9E9E9E,
    this.kind = 'expense',
    this.children = const <SeedCategoryNode>[],
  });

  final String id;
  final String name;
  final String iconKey;
  final int color;

  /// `expense` or `income`, matching the `categories.kind` column.
  final String kind;

  final List<SeedCategoryNode> children;
}
