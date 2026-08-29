/// Domain-side mirrors of three enums declared in `nimbus_data`'s
/// transactions table.
///
/// `QuerySpec` has to name these values, and `nimbus_domain` is forbidden from
/// importing `nimbus_data` -- the same wall Phase 2A hit with `TxDirection`,
/// and the same answer. The compiler in `nimbus_data` maps between the two
/// families at the boundary, and a mapping-completeness test there fails if
/// either side gains a value the other lacks.
///
/// The `name` strings are the contract. Do not rename a value without changing
/// its counterpart in the same commit.
library;

/// Mirrors `TxDirection`.
enum MoneyDirection { expense, income }

/// Mirrors `Necessity`.
enum NecessityLevel { needed, optional, avoidable }

/// Mirrors `Satisfaction`.
enum SatisfactionLevel { glad, neutral, regret }
