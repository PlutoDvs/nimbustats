import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A buffer line the drain refused, and why (spec §2.3).
typedef RejectedLine = ({String line, String reason});

/// What Android shows for the two notification channels, in the app's
/// language (spec §4.1).
typedef ChannelTexts = ({
  String alertsName,
  String alertsDescription,
  String reminderName,
  String reminderDescription,
});

/// The one boundary between Dart and Phase 6's Android code: the
/// `com.nimbustats.app/outside` channel, exactly as spec §1.1 lists it.
///
/// Every test replaces it with a fake (`FakeOutsideChannel`). A method that
/// must return a value and gets null throws: a missing answer from native is
/// a bug to see, not a default to assume.
class OutsideChannel {
  OutsideChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(name) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const name = 'com.nimbustats.app/outside';

  final MethodChannel _channel;
  final _routes = StreamController<String>.broadcast();

  /// Runs a drain when native asks the app engine for one (`drainNow`), and
  /// says whether every line was settled.
  ///
  /// Null until `WidgetSync` mounts. Native then hears "not implemented" and
  /// drains in a headless engine instead (spec §2.4).
  Future<bool> Function()? onDrainNow;

  /// Routes of notifications tapped while the app runs (`openRoute`).
  Stream<String> get routes => _routes.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'drainNow':
        final drain = onDrainNow;
        if (drain == null) {
          throw MissingPluginException('no drain handler is registered yet');
        }
        return drain();
      case 'openRoute':
        _routes.add(call.arguments as String);
        return null;
      default:
        throw MissingPluginException('${call.method} is not a native call');
    }
  }

  Future<bool> notificationsEnabled() => _require<bool>('notificationsEnabled');

  /// Asks for Android 13's POST_NOTIFICATIONS in context. Below 13 it answers
  /// whether notifications are enabled, with no dialog.
  Future<bool> requestNotificationPermission() =>
      _require<bool>('requestNotificationPermission');

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<void> registerChannels(ChannelTexts texts) =>
      _channel.invokeMethod<void>('registerChannels', {
        'alertsName': texts.alertsName,
        'alertsDescription': texts.alertsDescription,
        'reminderName': texts.reminderName,
        'reminderDescription': texts.reminderDescription,
      });

  Future<void> postAlert({
    required String tag,
    required String text,
    required String publicText,
    required String route,
  }) =>
      _channel.invokeMethod<void>('postAlert', {
        'tag': tag,
        'text': text,
        'publicText': publicText,
        'route': route,
      });

  /// Arms the daily reminder at [minuteOfDay] local time, or cancels it.
  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
    required String text,
    required String route,
  }) =>
      _channel.invokeMethod<void>('setReminder', {
        'enabled': enabled,
        'minuteOfDay': minuteOfDay,
        'text': text,
        'route': route,
      });

  /// Stores [json] as the widget snapshot and re-renders every widget.
  Future<void> writeSnapshot(String json) =>
      _channel.invokeMethod<void>('writeSnapshot', {'snapshot': json});

  /// Every pending buffer line, raw. Nothing is removed.
  Future<List<String>> takeBuffer() async =>
      (await _require<List<Object?>>('takeBuffer')).cast<String>();

  /// Under the buffer lock, in one call: writes [snapshot], drops the acked
  /// and rejected lines, and keeps the rejected ones with their reasons
  /// (spec §2.3 step 4).
  Future<void> commitDrain({
    required String snapshot,
    required List<String> ackIds,
    required List<RejectedLine> rejected,
  }) =>
      _channel.invokeMethod<void>('commitDrain', {
        'snapshot': snapshot,
        'ackIds': ackIds,
        'rejected': [
          for (final r in rejected) {'line': r.line, 'reason': r.reason},
        ],
      });

  /// The headless engine's last word: native then destroys it.
  Future<void> drainFinished(bool ok) =>
      _channel.invokeMethod<void>('drainFinished', {'ok': ok});

  /// The route a notification tap launched the app with, once.
  Future<String?> takeLaunchRoute() =>
      _channel.invokeMethod<String>('takeLaunchRoute');

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_routes.close());
  }

  Future<T> _require<T>(String method) async {
    final value = await _channel.invokeMethod<T>(method);
    if (value == null) {
      throw PlatformException(
          code: 'null-reply', message: '$method answered null');
    }
    return value;
  }
}

/// The app's one channel. The headless drain engine overrides it with the
/// channel it built, so both engines read the same provider.
final outsideChannelProvider = Provider<OutsideChannel>((ref) {
  final channel = OutsideChannel();
  ref.onDispose(channel.dispose);
  return channel;
});
