import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/application/category_providers.dart';
import '../../categories/data/category_tree.dart';
import '../../settings/application/settings_providers.dart';
import '../application/transaction_list_controller.dart';
import '../routes.dart';
import 'widgets/transaction_row.dart';

/// The app's home screen: what was spent, grouped by day, newest first.
class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    // Eighty per cent rather than the very end, so the next page is usually
    // already there by the time the user reaches the bottom.
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      // The controller refuses overlapping requests, which is what makes it
      // safe to call this on every scroll notification.
      unawaited(
        ref.read(transactionListControllerProvider.notifier).loadMore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(transactionListControllerProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final tree = ref.watch(categoryTreeProvider).value ?? const [];
    final byId = {
      for (final node in CategoryTree.flatten(tree)) node.category.id: node,
    };

    // hasError/hasValue rather than a switch over the AsyncValue subtypes --
    // see CategoryManagerScreen for why the subtypes lie here.
    final state = async.hasError ? null : async.value;

    final Widget body;
    if (async.hasError) {
      body = NimbusErrorState(
        title: l10n.txListErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: async.error.toString(),
        onRetry: () => ref.invalidate(transactionListControllerProvider),
      );
    } else if (state == null) {
      body = const NimbusLoadingList(rows: 8);
    } else if (state.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.receipt_long_outlined,
        title: l10n.txListEmptyTitle,
        message: l10n.txListEmptyMessage,
        actionLabel: l10n.addExpense,
        onAction: () => context.push(addTransactionRoute),
      );
    } else {
      body = _List(
        state: state,
        formatter: formatter,
        categories: byId,
        scroll: _scroll,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.txListTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NimbusTokens.space4,
              0,
              NimbusTokens.space4,
              NimbusTokens.space2,
            ),
            child: TextField(
              key: const Key('tx-search'),
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.txSearchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => ref
                  .read(transactionListControllerProvider.notifier)
                  .setSearch(value),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (state != null)
            _MonthTotal(state: state, formatter: formatter),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('tx-add-fab'),
        onPressed: () => context.push(addTransactionRoute),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MonthTotal extends ConsumerWidget {
  const _MonthTotal({required this.state, required this.formatter});

  final TransactionListState state;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(transactionListControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NimbusTokens.space4,
        vertical: NimbusTokens.space2,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('tx-period-previous'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => controller.shiftPeriod(-1),
          ),
          Expanded(
            child: Column(
              children: [
                Text(l10n.txMonthTotal, style: theme.textTheme.labelMedium),
                Text(
                  // Full format, never compact: this is the number the whole
                  // screen exists to show.
                  formatter.format(state.monthTotal),
                  key: const Key('tx-month-total'),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('tx-period-next'),
            icon: const Icon(Icons.chevron_right),
            onPressed: () => controller.shiftPeriod(1),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({
    required this.state,
    required this.formatter,
    required this.categories,
    required this.scroll,
  });

  final TransactionListState state;
  final MoneyFormatter formatter;
  final Map<String, CategoryNode> categories;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final calendar = ref.watch(calendarProvider);

    return CustomScrollView(
      controller: scroll,
      slivers: [
        for (final group in state.groups) ...[
          SliverToBoxAdapter(
            child: Container(
              key: Key('day-header-${group.day.value}'),
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(
                horizontal: NimbusTokens.space4,
                vertical: NimbusTokens.space2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dayLabel(calendar, group.day, formatter.persianDigits),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    formatter.format(group.subtotal),
                    key: Key('day-subtotal-${group.day.value}'),
                    style: theme.textTheme.labelLarge,
                    semanticsLabel: l10n.txDaySubtotal,
                  ),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: group.rows.length,
            itemBuilder: (context, index) {
              final transaction = group.rows[index];
              return TransactionRow(
                key: Key('tx-${transaction.id}'),
                transaction: transaction,
                category: categories[transaction.categoryId],
                formatter: formatter,
                onTap: () {},
              );
            },
          ),
        ],
        if (state.hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(NimbusTokens.space4),
              child: Center(
                child: TextButton(
                  key: const Key('tx-load-more'),
                  onPressed: () => ref
                      .read(transactionListControllerProvider.notifier)
                      .loadMore(),
                  child: Text(l10n.txLoadMore),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Rendered through the active calendar, so a Jalali user sees a Jalali date
  /// rather than a Gregorian one to convert in their head.
  static String _dayLabel(
    AppCalendar calendar,
    DateKey day,
    bool persianDigits,
  ) {
    final parts = calendar.partsOf(day);
    final text = '${parts.year}/'
        '${parts.month.toString().padLeft(2, '0')}/'
        '${parts.day.toString().padLeft(2, '0')}';
    return persianDigits ? Digits.toPersian(text) : text;
  }
}
