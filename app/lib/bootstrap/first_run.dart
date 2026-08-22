import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../features/categories/data/default_category_tree.dart';
import '../features/settings/data/settings_keys.dart';
import '../l10n/app_localizations.dart';
import 'database_provider.dart';

/// Everything that has to happen exactly once, on the first launch of an
/// install, before any screen needs a category to point at.
///
/// Takes [AppLocalizations] as an argument rather than resolving it from a
/// provider, so seeding stays a plain data operation that can be driven and
/// tested without a widget tree.
final class FirstRunController {
  const FirstRunController(this._db);

  final AppDatabase _db;

  /// Seeds the default tree if the database has never been seeded, and returns
  /// whether it did.
  ///
  /// Safe to call on every launch: the emptiness check inside [CategorySeeder]
  /// is what makes it idempotent, and the install stamps below are only
  /// written when seeding actually happened, so `installed_at` records the
  /// first launch rather than the most recent one.
  ///
  /// Note that a user who switches language later keeps the tree they have.
  /// Re-labelling categories they may have renamed, merged, or reorganised
  /// would be destructive, and the tree stops being ours the moment it exists.
  Future<bool> ensureSeeded(AppLocalizations l10n) async {
    final seeded = await CategorySeeder(_db).seedIfEmpty(
      roots: defaultCategoryTree(l10n),
      uncategorizedName: l10n.uncategorized,
    );
    if (!seeded) return false;

    final settings = _db.settingsDao;
    await settings.put(
      SettingsKeys.installedAt,
      DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
    );
    await settings.put(SettingsKeys.seedVersion, '1');
    // Founding users retain full access permanently once gates are switched
    // on, so this has to be written the moment the install exists rather than
    // at some later point when the cutoff might already have passed.
    await settings.put(SettingsKeys.foundingUser, 'true');
    return true;
  }
}

final firstRunControllerProvider = Provider<FirstRunController>(
  (ref) => FirstRunController(ref.watch(appDatabaseProvider)),
);
