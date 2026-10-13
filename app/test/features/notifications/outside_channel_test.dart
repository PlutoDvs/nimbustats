import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';

/// The Dart half of spec §1.1, against a mocked platform side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel(OutsideChannel.name);
  const codec = StandardMethodCodec();

  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;
  late OutsideChannel outside;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call);
      return reply(call);
    });
    outside = OutsideChannel();
  });
  tearDown(() {
    outside.dispose();
    messenger.setMockMethodCallHandler(platform, null);
  });

  /// A call made by native code, as the app engine receives it.
  Future<ByteData?> fromNative(String method, [Object? arguments]) {
    final answered = Completer<ByteData?>();
    messenger.handlePlatformMessage(OutsideChannel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        answered.complete);
    return answered.future;
  }

  test('commitDrain sends the snapshot, the acks and the rejects', () async {
    await outside.commitDrain(
      snapshot: '{"v":1}',
      ackIds: const ['a', 'b'],
      rejected: const [(line: 'x', reason: 'malformed line')],
    );
    expect(calls.single.method, 'commitDrain');
    expect(calls.single.arguments, {
      'snapshot': '{"v":1}',
      'ackIds': ['a', 'b'],
      'rejected': [
        {'line': 'x', 'reason': 'malformed line'},
      ],
    });
  });

  test('postAlert and setReminder carry exactly the spec arguments', () async {
    await outside.postAlert(
        tag: 'goal:g1', text: 'full', publicText: 'discreet', route: '/goals/g1');
    await outside.setReminder(
        enabled: true, minuteOfDay: 1260, text: 'Log?', route: '/add');
    expect(calls[0].arguments, {
      'tag': 'goal:g1',
      'text': 'full',
      'publicText': 'discreet',
      'route': '/goals/g1',
    });
    expect(calls[1].arguments, {
      'enabled': true,
      'minuteOfDay': 1260,
      'text': 'Log?',
      'route': '/add',
    });
  });

  test('takeBuffer returns the raw lines', () async {
    reply = (_) => ['{"v":1}', 'garbage'];
    expect(await outside.takeBuffer(), ['{"v":1}', 'garbage']);
  });

  test('a null reply where a value is required is an error, not a default',
      () async {
    reply = (_) => null;
    expect(outside.notificationsEnabled(), throwsA(isA<PlatformException>()));
    expect(outside.takeBuffer(), throwsA(isA<PlatformException>()));
  });

  test('drainNow with no drain registered answers not-implemented, so '
      'native drains in a headless engine', () async {
    expect(await fromNative('drainNow'), isNull);
  });

  test('drainNow runs the registered drain and replies with its result',
      () async {
    outside.onDrainNow = () async => true;
    final answer = await fromNative('drainNow');
    expect(codec.decodeEnvelope(answer!), isTrue);
  });

  test('openRoute arrives on routes', () async {
    final routes = <String>[];
    final subscription = outside.routes.listen(routes.add);
    addTearDown(subscription.cancel);
    await fromNative('openRoute', '/goals/g1');
    await Future<void>.delayed(Duration.zero);
    expect(routes, ['/goals/g1']);
  });
}
