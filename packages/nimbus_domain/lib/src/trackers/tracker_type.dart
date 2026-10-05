/// What a tracker counts.
///
/// Fixed when the tracker is created. An entry's value means something
/// different under each type -- one cigarette, a day done, 2.5 litres, 5400
/// seconds -- so changing the type afterwards would silently reinterpret every
/// entry already logged.
///
/// Stored by name: reordering these values is free, renaming one is a
/// migration.
enum TrackerType { counter, boolean, quantity, duration }
