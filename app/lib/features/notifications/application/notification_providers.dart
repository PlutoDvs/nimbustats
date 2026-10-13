import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/notification_prefs.dart';

final notificationPrefsRepositoryProvider =
    Provider<NotificationPrefsRepository>((ref) =>
        NotificationPrefsRepository(ref.watch(appDatabaseProvider).settingsDao));

/// The reminder and detail settings, live: the settings section watches it.
final notificationPrefsProvider = StreamProvider<NotificationPrefs>(
    (ref) => ref.watch(notificationPrefsRepositoryProvider).watch());

/// Whether the app is on screen (spec §4.3). The headless drain engine has
/// no lifecycle, so it reads false there, and every alert becomes a
/// notification. Overridden in tests.
final isForegroundProvider = Provider<bool Function()>((ref) => () =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
