import 'dart:convert';

/// An expense line as the dialog appends it. 2026-10-05 09:00 UTC is the
/// fake clock's now.
String expense(String id,
        {int amount = 120000, String? category, DateTime? at}) =>
    jsonEncode({
      'v': 1,
      'id': id,
      'kind': 'expense',
      'atUtc': (at ?? DateTime.utc(2026, 10, 5, 9)).millisecondsSinceEpoch,
      'amountMinor': amount,
      'categoryId': category,
    });

/// A tracker tap line as the widget appends it.
String tap(String id, String trackerId, {DateTime? at}) => jsonEncode({
      'v': 1,
      'id': id,
      'kind': 'tracker',
      'atUtc': (at ?? DateTime.utc(2026, 10, 5, 9)).millisecondsSinceEpoch,
      'trackerId': trackerId,
    });
