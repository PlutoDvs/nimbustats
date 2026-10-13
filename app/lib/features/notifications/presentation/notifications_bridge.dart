import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../application/outside_errors.dart';
import '../data/outside_channel.dart';

/// Keeps Android's side of notifications in step with the app (spec §4.1,
/// §1.1):
/// - names the two channels in the app's language, at start and again
///   after a language switch;
/// - opens the route of a notification that launched the app, once, after
///   the first frame;
/// - opens the route of a notification tapped while the app runs.
///
/// It sits on the shell (ruling R6): the routes need the router, and
/// nothing posts before the app has run once, so the channels exist
/// whenever they are needed.
class NotificationsBridge extends ConsumerStatefulWidget {
  const NotificationsBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationsBridge> createState() =>
      _NotificationsBridgeState();
}

class _NotificationsBridgeState extends ConsumerState<NotificationsBridge> {
  late final OutsideChannel _channel;
  late final StreamSubscription<String> _routes;

  /// The locale the channels were last named in.
  Locale? _namedIn;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(outsideChannelProvider);
    _routes = _channel.routes.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final route = await reportingFailure(
        'alert router',
        'while reading the launch route',
        _channel.takeLaunchRoute,
      );
      if (route != null) _open(route);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _namedIn) return;
    _namedIn = locale;
    final l10n = AppLocalizations.of(context);
    unawaited(
      reportingFailure(
        'alert router',
        'while naming the notification channels',
        () => _channel.registerChannels((
          alertsName: l10n.notificationsAlertsChannelName,
          alertsDescription: l10n.notificationsAlertsChannelDescription,
          reminderName: l10n.notificationsReminderChannelName,
          reminderDescription: l10n.notificationsReminderChannelDescription,
        )),
      ),
    );
  }

  void _open(String route) {
    if (!mounted) return;
    unawaited(GoRouter.of(context).push(route));
  }

  @override
  void dispose() {
    unawaited(_routes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
