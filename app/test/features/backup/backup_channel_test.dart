import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';

/// The Dart half of spec §6, against a mocked platform side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel(BackupChannel.name);

  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call);
      return reply(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(platform, null));

  test('saveDocument sends the path and answers saved or cancelled', () async {
    reply = (_) => true;
    expect(await BackupChannel().saveDocument('/c/backup/out/a.nimbus'), isTrue);
    reply = (_) => false;
    expect(await BackupChannel().saveDocument('/c/backup/out/a.nimbus'), isFalse);
    for (final call in calls) {
      expect(call.method, 'saveDocument');
      expect(call.arguments, {'path': '/c/backup/out/a.nimbus'});
    }
  });

  test('a null answer to saveDocument is a bug to see, not a cancel',
      () async {
    await expectLater(BackupChannel().saveDocument('/x'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'null-reply')));
  });

  test('shareFile sends the path', () async {
    await BackupChannel().shareFile('/c/backup/out/a.nimbus');
    expect(calls.single.method, 'shareFile');
    expect(calls.single.arguments, {'path': '/c/backup/out/a.nimbus'});
  });

  test('openDocument answers the cache copy, or null when cancelled',
      () async {
    reply = (_) => '/c/backup/picked-1.nimbus';
    expect(await BackupChannel().openDocument(), '/c/backup/picked-1.nimbus');
    reply = (_) => null;
    expect(await BackupChannel().openDocument(), isNull);
  });

  test('a native failure arrives as a PlatformException', () async {
    messenger.setMockMethodCallHandler(platform,
        (call) async => throw PlatformException(code: 'io', message: 'IOException'));
    await expectLater(BackupChannel().openDocument(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'io')));
  });
}
