import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps Override out of the main barrel.
import 'package:flutter_riverpod/misc.dart';

import '../../../bootstrap/provider_retry.dart';
import '../application/restart.dart';

/// The root of the running app: one [ProviderScope] that a restore can
/// replace with a fresh one (spec §5.3).
///
/// The `AppDatabase` stays the same object, and its file's content changed
/// in place. Every provider, the router included, starts again. So does
/// whatever the shell does at start, Phase 6's reminder push and widget
/// snapshot among it.
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.overrides, required this.child});

  final List<Override> overrides;
  final Widget child;

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  var _generation = 0;
  var _between = false;
  RestartNotice? _notice;

  void _restart(RestartNotice notice) {
    // Two frames (ruling R3): the old scope is disposed before the new one
    // builds. Phase 6's OutsideChannel clears the channel's shared handler
    // when disposed. Disposed after the new scope had set its own, it would
    // silence every native call for the rest of the run.
    setState(() {
      _between = true;
      _notice = notice;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _between = false;
        _generation++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_between) return const SizedBox.shrink();
    return ProviderScope(
      key: ValueKey(_generation),
      retry: nimbusNoRetry,
      overrides: [
        ...widget.overrides,
        appRestartProvider.overrideWithValue(_restart),
        restartNoticeProvider.overrideWithValue(_notice),
      ],
      child: widget.child,
    );
  }
}
