/// The app's provider retry policy.
///
/// Riverpod 3 retries any failed provider on its own, with exponential
/// backoff starting at 200ms and no upper bound on attempts. That default is
/// written for network-backed providers; every provider in this app reads
/// local SQLite, where a failure means a corrupt file or a schema problem and
/// retrying will not fix it.
///
/// Leaving it on is actively harmful here. The retry flips `AsyncValue.
/// retrying` on and off, so an error screen bounces between its error state
/// and its skeleton without the user touching anything -- an error that never
/// settles is one the user cannot report and the operator cannot see. Every
/// screen already offers an explicit retry, which is the honest affordance.
///
/// Returning null means "do not retry". A provider that genuinely wants one
/// can opt in individually via its own `retry:` argument, which is why this is
/// a default rather than a prohibition.
Duration? nimbusNoRetry(int retryCount, Object error) => null;
