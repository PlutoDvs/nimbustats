import 'package:flutter/foundation.dart';

/// Runs [action]. A failure is reported through [FlutterError.reportError]
/// under [library] (spec §9), and null is returned.
///
/// For the fire-and-forget calls that cross the platform channel: a
/// rethrown error there would surface as an unhandled async error with no
/// context, and an ignored one would be a silent failure.
Future<T?> reportingFailure<T>(
  String library,
  String context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on Object catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: library,
      context: ErrorDescription(context),
    ));
    return null;
  }
}
