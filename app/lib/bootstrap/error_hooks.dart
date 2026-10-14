import 'package:flutter/foundation.dart';

/// Reports every error this isolate leaves uncaught through
/// [FlutterError.reportError] under [library] (D12), the channel
/// `reportingFailure` already uses. That is logcat until Phase 8 picks crash
/// reporting; nothing is persisted.
///
/// Framework errors already reach [FlutterError.onError]. This catches the
/// rest: a write rethrown from an event handler, an error in a future nothing
/// awaited. Each engine runs its own isolate, so each entry point installs
/// its own.
void installErrorHooks(String library) {
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: library,
      context: ErrorDescription('and nothing caught it'),
    ));
    // Handled: reported once here, not printed again by the engine.
    return true;
  };
}
