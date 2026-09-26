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

  /// Whether first run has happened on this install: the category tree exists.
  ///
  /// The tree rather than `AppSettings.onboardingCompleted`, because the tree
  /// is what everything past onboarding actually needs -- every transaction
  /// points into it -- and it is the one that cannot disagree with itself.
  /// The flag is written before seeding and wiped by a settings reset, so it
  /// can say "done" over an empty table, or "not done" over a full one.
  Future<bool> isComplete() => CategorySeeder(_db).hasSeeded();

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

/// The question the router's first-run gate asks.
///
/// A provider of its own so a screen test on a deliberately empty database --
/// one that is not about first run -- can answer it rather than being turned
/// away to onboarding.
final firstRunCompleteProvider = Provider<Future<bool> Function()>(
  (ref) => ref.watch(firstRunControllerProvider).isComplete,
);
