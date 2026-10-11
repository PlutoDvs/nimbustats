/// Which side of its target a goal wants to end on.
///
/// The `name` strings are stored in `goals.direction`. Do not rename a value.
enum GoalDirection {
  /// Stay at or below the target.
  atMost,

  /// Reach the target.
  atLeast,
}
