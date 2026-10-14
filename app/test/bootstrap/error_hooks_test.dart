import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/bootstrap/error_hooks.dart';

/// D12: an error nothing caught is reported, not lost.
void main() {
  test('an uncaught error is reported under the library and marked handled',
      () {
    // dart:ui's own dispatcher. The test binding's wrapper drops an onError
    // assignment, so a hook set through it would never run here.
    final dispatcher = PlatformDispatcher.instance;
    final previousHook = dispatcher.onError;
    addTearDown(() => dispatcher.onError = previousHook);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    installErrorHooks('nimbustats');
    final error = StateError('a write nobody awaited');
    final stack = StackTrace.current;

    expect(dispatcher.onError!(error, stack), isTrue);
    expect(reported, hasLength(1));
    expect(reported.single.library, 'nimbustats');
    expect(reported.single.exception, same(error));
    expect(reported.single.stack, same(stack));
  });
}
