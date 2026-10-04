import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../categories/data/category_tree.dart';
import '../../../payment_methods/application/payment_method_providers.dart';
import '../../../tags/application/tag_providers.dart';
import '../../../transactions/application/transaction_list_controller.dart';
import '../../../transactions/application/transaction_providers.dart';
import '../../application/demo_data_seeder.dart';

/// Debug-only: fills the database with enough history to measure against.
///
/// The 60 fps acceptance criterion is stated against 5,000 transactions, and
/// nobody is going to type those in. Building this as a settings action is the
/// difference between measuring that number on a device and writing "not
/// measured" in the definition of done. What the rows look like is
/// [DemoDataSeeder]'s business.
///
/// Guarded by `kDebugMode` at the call site, so the constant folds it out of a
/// release build entirely rather than leaving it merely unreachable.
class DemoDataTile extends ConsumerStatefulWidget {
  const DemoDataTile({super.key});

  @override
  ConsumerState<DemoDataTile> createState() => _DemoDataTileState();
}

class _DemoDataTileState extends ConsumerState<DemoDataTile> {
  bool _running = false;

  Future<void> _seed() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // Awaited, not read: on a launch straight into settings the tree may still
    // be loading, and reading it as empty would refuse to seed a database that
    // has a full one. It resolves because build() watches it -- see there.
    final tree = await ref.read(categoryTreeProvider.future);
    final categories = CategoryTree.flatten(tree)
        .map((n) => n.category.id)
        .where((id) => !SystemCategoryIds.isSystem(id))
        .toList();
    if (categories.isEmpty) {
      // Said rather than skipped: a button that does nothing reads as broken.
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.settingsDebugSeedNoCategories)));
      return;
    }

    setState(() => _running = true);
    try {
      final paymentMethods =
          await ref.read(paymentMethodRepositoryProvider).pickable();
      await DemoDataSeeder(
        transactions: ref.read(transactionRepositoryProvider),
        tags: ref.read(tagRepositoryProvider),
        categoryIds: categories,
        paymentMethodIds: [for (final method in paymentMethods) method.id],
        nowUtc: DateTime.now().toUtc(),
      ).seed();
      await ref.read(transactionListControllerProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Watched for _seed's sake, not for rendering. Riverpod 3 pauses a
    // StreamProvider's subscription while nothing is listening, and nothing
    // else on the settings screen watches the tree -- so a bare read of its
    // future from here never completed, and the button did nothing.
    ref.watch(categoryTreeProvider);

    return ListTile(
      key: const Key('settings-debug-seed'),
      leading: const Icon(Icons.science_outlined),
      title: Text(l10n.settingsDebugSeed),
      // The one progress indicator in the app, because this genuinely takes
      // time. The rule forbids a spinner on a save, not on real work.
      trailing: _running
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      enabled: !_running,
      onTap: _running ? null : _seed,
    );
  }
}
