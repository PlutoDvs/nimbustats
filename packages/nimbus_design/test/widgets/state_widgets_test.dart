import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

void main() {
  Widget host(Widget child, {TextDirection direction = TextDirection.rtl}) =>
      MaterialApp(
        theme: NimbusTheme.light(),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(body: child),
        ),
      );

  group('NimbusEmptyState', () {
    testWidgets('shows the title, the message, and the action', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(NimbusEmptyState(
        icon: Icons.receipt_long,
        title: 'Nothing here yet',
        message: 'Log your first expense to see it appear.',
        actionLabel: 'Add expense',
        onAction: () => tapped++,
      )));

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
          find.text('Log your first expense to see it appear.'), findsOneWidget);

      await tester.tap(find.text('Add expense'));
      expect(tapped, 1,
          reason: 'an empty state that says what to do next must let you do it');
    });

    testWidgets('omits the action when none is given', (tester) async {
      await tester.pumpWidget(host(const NimbusEmptyState(
        icon: Icons.sell,
        title: 'No tags',
        message: 'Tags group expenses across categories.',
      )));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders right-to-left without overflowing', (tester) async {
      await tester.pumpWidget(host(const NimbusEmptyState(
        icon: Icons.sell,
        title: 'برچسبی وجود ندارد',
        message: 'برچسب‌ها هزینه‌ها را فراتر از دسته‌بندی گروه‌بندی می‌کنند.',
      )));
      expect(tester.takeException(), isNull);
      expect(find.text('برچسبی وجود ندارد'), findsOneWidget);
    });

    testWidgets('the action meets the minimum tap target', (tester) async {
      await tester.pumpWidget(host(NimbusEmptyState(
        icon: Icons.receipt_long,
        title: 'Nothing here yet',
        message: 'Log your first expense.',
        actionLabel: 'Add',
        onAction: () {},
      )));
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(NimbusTokens.minTapTarget));
    });
  });

  group('NimbusErrorState', () {
    testWidgets('offers a retry and never shows a raw exception',
        (tester) async {
      var retried = 0;
      await tester.pumpWidget(host(NimbusErrorState(
        title: 'Could not load transactions',
        retryLabel: 'Retry',
        onRetry: () => retried++,
        detail: 'DatabaseException: no such table: transactions',
      )));

      expect(find.text('Could not load transactions'), findsOneWidget);
      // The detail is carried but not shouted: the contract forbids a bare
      // exception string as the error state.
      expect(find.text('DatabaseException: no such table: transactions'),
          findsNothing);

      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });
  });

  group('NimbusLoadingList', () {
    testWidgets('renders skeleton rows, not a blocking spinner', (tester) async {
      await tester.pumpWidget(host(const NimbusLoadingList(rows: 4)));
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the contract forbids a blocking spinner for a read');
      expect(find.byKey(const Key('nimbus-skeleton-row')), findsNWidgets(4));
    });
  });

  group('nimbusUndoSnackBar', () {
    testWidgets('carries an undo action rather than a confirmation',
        (tester) async {
      var undone = 0;
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      })));

      ScaffoldMessenger.of(ctx).showSnackBar(nimbusUndoSnackBar(
        message: 'Deleted',
        undoLabel: 'Undo',
        onUndo: () => undone++,
      ));
      // Settle the entrance animation before tapping: mid-transition the
      // action is laid out off its final position and the tap misses.
      await tester.pumpAndSettle();

      expect(find.text('Deleted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, 1);
    });
  });
}
