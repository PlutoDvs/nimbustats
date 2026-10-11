/// Where a goal stands for one period.
enum GoalStatus {
  /// Today is before the period, or before the goal's own start.
  notStarted,

  /// Open, and nothing to warn about.
  onTrack,

  /// Open: a cap past its lowest alert percent, or a goal behind pace.
  atRisk,

  /// A cap gone over, open or closed.
  exceeded,

  /// A goal reached, or a closed period that stayed within its cap.
  met,

  /// A closed period short of a goal. `exceeded` is a cap's failure, not a
  /// minimum's, so a minimum that fell short needs its own word.
  missed,
}
