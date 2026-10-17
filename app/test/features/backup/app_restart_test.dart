import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/presentation/app_restart.dart';

void main() {
  testWidgets(
      'a restart disposes the old scope before the new one builds (R3), '
      'and hands the new one its notice', (tester) async {
    final log = <String>[];
    var created = 0;
    final probe = Provider<int>((ref) {
      final generation = created++;
      log.add('create $generation');
      ref.onDispose(() => log.add('dispose $generation'));
      return generation;
    });
    late void Function(RestartNotice) restart;

    await tester.pumpWidget(AppRestart(
      overrides: const [],
      child: Consumer(builder: (context, ref, _) {
        restart = ref.read(appRestartProvider);
        final generation = ref.watch(probe);
        final notice = ref.watch(restartNoticeProvider);
        return Text('$generation ${notice.runtimeType}',
            textDirection: TextDirection.ltr);
      }),
    ));
    expect(find.text('0 Null'), findsOneWidget);

    restart(const RestoreUndone());
    await tester.pump();
    // The frame in between: the old scope is gone and the new one is not
    // built yet. Phase 6's channel handler is cleared before it is re-set.
    expect(log, ['create 0', 'dispose 0']);

    await tester.pump();
    expect(log, ['create 0', 'dispose 0', 'create 1']);
    expect(find.text('1 RestoreUndone'), findsOneWidget);
  });
}
