import '../data/outside_channel.dart';
import 'outside_errors.dart';

/// Asks for the notification permission in context (spec §4.2): after the
/// first goal is saved, and when the reminder is switched on. Never at first
/// launch.
///
/// Android does the rest. A granted permission answers at once with no
/// dialog, and after two denials it shows nothing, so no "already asked"
/// state is kept here. A channel failure is reported under [library] and
/// reads as not granted.
Future<bool> askForNotifications(
  OutsideChannel channel, {
  required String library,
}) async =>
    await reportingFailure(library,
        'while asking for the notification permission',
        channel.requestNotificationPermission) ??
    false;
