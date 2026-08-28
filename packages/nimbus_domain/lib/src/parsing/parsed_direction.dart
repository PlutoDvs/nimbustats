/// Which way money moved, as the parsing layer sees it.
///
/// Deliberately not `TxDirection`: that enum lives in `nimbus_data`, and
/// `nimbus_domain` is forbidden from depending on it by
/// `test/architecture_test.dart`. Phase 2B maps debit to expense and credit
/// to income at the ingestion boundary.
enum ParsedDirection { debit, credit }
