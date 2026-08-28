import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'message_normalizer.dart';

/// Milliseconds in the bucket two deliveries must share to be called the
/// same message.
const _bucketMillis = 60 * 1000;

/// A stable identity for one captured message.
///
/// Stored in `captured_messages.dedup_hash`, which is `UNIQUE` at the
/// database level: double-counting is made structurally impossible rather
/// than merely checked for in Dart.
///
/// SHA-256 rather than something cheaper because that UNIQUE constraint turns
/// a collision into *data loss* — the colliding message cannot be stored at
/// all, and the whole capture design rests on never losing a raw message.
///
/// The body is normalized first, so the same message re-delivered with
/// Persian digits or a stray bidi mark still dedups; a carrier retry must not
/// become a second expense.
///
/// The receipt time is bucketed to the minute, which is a deliberate trade:
/// two byte-identical messages from one sender inside the same minute
/// collapse to one. Double-counting money is worse than missing a genuine
/// repeat purchase that fast. The boundary is sharp — 10:00:59 and 10:01:00
/// are different buckets — and the database constraint, not this function, is
/// the real guard.
String dedupHash({
  required String sender,
  required String body,
  required DateTime receivedAt,
}) {
  final bucket = receivedAt.toUtc().millisecondsSinceEpoch ~/ _bucketMillis;
  final payload = '$sender|${MessageNormalizer.normalize(body)}|$bucket';
  return sha256.convert(utf8.encode(payload)).toString();
}
