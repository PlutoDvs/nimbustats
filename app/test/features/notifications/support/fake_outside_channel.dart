import 'dart:async';
import 'dart:convert';

import 'package:nimbustats/features/notifications/data/outside_channel.dart';

/// [OutsideChannel] without Android. It records every call and plays the
/// native side's part: the buffer, the permission, the launch route.
class FakeOutsideChannel implements OutsideChannel {
  /// Method names, in call order.
  final calls = <String>[];

  bool enabled = true;

  /// What the permission dialog answers. Granting also enables.
  bool grant = true;
  int permissionRequests = 0;
  int settingsOpened = 0;

  /// Thrown by the next [postAlert], to test a failed post.
  Exception? postError;

  /// Thrown by [takeBuffer] while set, to test a failed drain.
  Exception? takeError;

  /// The native buffer's lines.
  List<String> buffer = [];
  String? launchRoute;

  final channelTexts = <ChannelTexts>[];
  final posted =
      <({String tag, String text, String publicText, String route})>[];
  final reminders =
      <({bool enabled, int minuteOfDay, String text, String route})>[];
  final snapshots = <String>[];
  final commits = <({
    String snapshot,
    List<String> ackIds,
    List<RejectedLine> rejected,
  })>[];
  final finished = <bool>[];

  final _routes = StreamController<String>.broadcast();

  /// A notification tapped while the app runs, as native sends it.
  void tapRoute(String route) => _routes.add(route);

  @override
  Future<bool> Function()? onDrainNow;

  @override
  Stream<String> get routes => _routes.stream;

  @override
  Future<bool> notificationsEnabled() async {
    calls.add('notificationsEnabled');
    return enabled;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    permissionRequests++;
    if (grant) enabled = true;
    return grant;
  }

  @override
  Future<void> openNotificationSettings() async {
    calls.add('openNotificationSettings');
    settingsOpened++;
  }

  @override
  Future<void> registerChannels(ChannelTexts texts) async {
    calls.add('registerChannels');
    channelTexts.add(texts);
  }

  @override
  Future<void> postAlert({
    required String tag,
    required String text,
    required String publicText,
    required String route,
  }) async {
    calls.add('postAlert');
    final error = postError;
    if (error != null) throw error;
    posted.add((tag: tag, text: text, publicText: publicText, route: route));
  }

  @override
  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
    required String text,
    required String route,
  }) async {
    calls.add('setReminder');
    reminders.add((
      enabled: enabled,
      minuteOfDay: minuteOfDay,
      text: text,
      route: route,
    ));
  }

  @override
  Future<void> writeSnapshot(String json) async {
    calls.add('writeSnapshot');
    snapshots.add(json);
  }

  @override
  Future<List<String>> takeBuffer() async {
    calls.add('takeBuffer');
    final error = takeError;
    if (error != null) throw error;
    return List.of(buffer);
  }

  /// Drops what native would: acked ids and rejected lines.
  @override
  Future<void> commitDrain({
    required String snapshot,
    required List<String> ackIds,
    required List<RejectedLine> rejected,
  }) async {
    calls.add('commitDrain');
    commits.add((snapshot: snapshot, ackIds: ackIds, rejected: rejected));
    snapshots.add(snapshot);
    final acked = ackIds.toSet();
    final refused = {for (final r in rejected) r.line};
    buffer.removeWhere(
        (line) => refused.contains(line) || acked.contains(_idOf(line)));
  }

  @override
  Future<void> drainFinished(bool ok) async {
    calls.add('drainFinished');
    finished.add(ok);
  }

  @override
  Future<String?> takeLaunchRoute() async {
    calls.add('takeLaunchRoute');
    final route = launchRoute;
    launchRoute = null;
    return route;
  }

  @override
  void dispose() => unawaited(_routes.close());

  static String? _idOf(String line) {
    try {
      return (jsonDecode(line) as Map<String, Object?>)['id'] as String?;
    } on Object {
      return null;
    }
  }
}
