import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/first_run.dart';
import 'package:nimbustats/features/categories/data/default_category_tree.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late AppLocalizations en;
  late AppLocalizations fa;

  setUpAll(() async {
    // Loading the delegate directly keeps this a pure data test: first-run
    // seeding has no UI, so it should not need a widget tree to be exercised.
    en = await AppLocalizations.delegate.load(const Locale('en'));
    fa = await AppLocalizations.delegate.load(const Locale('fa'));
  });

  setUp(() {
    db = AppDatabase.openInMemory();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  FirstRunController controller() => container.read(firstRunControllerProvider);

  test('first launch seeds the English tree', () async {
    expect(await controller().ensureSeeded(en), isTrue);

    final categories = await db.categoriesDao.allLive();
    expect(categories, isNotEmpty);
    expect(categories.map((c) => c.name), contains('Food & drink'));
    expect(categories.map((c) => c.name), contains('Groceries'));
    expect(categories.map((c) => c.name), contains('Salary'));
  });

  test('the Persian tree is seeded in Persian', () async {
    expect(await controller().ensureSeeded(fa), isTrue);
    final names = (await db.categoriesDao.allLive()).map((c) => c.name);
    expect(names, contains('خوراک و نوشیدنی'));
    expect(names, contains('حقوق'));
  });

  test('the Uncategorized row takes its localized name', () async {
    await controller().ensureSeeded(fa);
    final row = await db.categoriesDao.byId(SystemCategoryIds.uncategorized);
    expect(row!.name, fa.uncategorized);
    expect(row.name, isNot(en.uncategorized));
  });

  test('a second launch does not re-seed', () async {
    await controller().ensureSeeded(en);
    final first = (await db.categoriesDao.allLive()).length;

    await db.categoriesDao.rename(SystemCategoryIds.uncategorized, 'Renamed');
    expect(await controller().ensureSeeded(en), isFalse);

    expect((await db.categoriesDao.allLive()), hasLength(first));
    expect((await db.categoriesDao.byId(SystemCategoryIds.uncategorized))!.name,
        'Renamed');
  });

  test('switching language does not re-seed in the new language', () async {
    // The tree belongs to the user once it exists. Re-labelling categories
    // they may have renamed, merged, or reorganised would be destructive.
    await controller().ensureSeeded(en);
    expect(await controller().ensureSeeded(fa), isFalse);
    expect((await db.categoriesDao.allLive()).map((c) => c.name),
        contains('Food & drink'));
  });

  test('first run stamps installedAt, seed version, and founding user',
      () async {
    await controller().ensureSeeded(en);

    final installedAt = await db.settingsDao.get(SettingsKeys.installedAt);
    expect(installedAt, isNotNull);
    expect(int.parse(installedAt!), greaterThan(0));
    expect(await db.settingsDao.get(SettingsKeys.seedVersion), '1');
    // Set before the early-access cutoff: founding users keep full access
    // permanently, so this has to be written the moment the install exists.
    expect(await db.settingsDao.get(SettingsKeys.foundingUser), 'true');
  });

  test('a second launch does not restamp installedAt', () async {
    await controller().ensureSeeded(en);
    final first = await db.settingsDao.get(SettingsKeys.installedAt);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller().ensureSeeded(en);
    expect(await db.settingsDao.get(SettingsKeys.installedAt), first);
  });

  group('the default tree itself', () {
    test('every id is unique', () {
      final ids = <String>[];
      void walk(List<SeedCategoryNode> nodes) {
        for (final node in nodes) {
          ids.add(node.id);
          walk(node.children);
        }
      }

      walk(defaultCategoryTree(en));
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('no seeded id collides with the system row', () {
      // A seed node with the reserved id would make the system category
      // deletable through an ordinary path.
      final ids = <String>[];
      void walk(List<SeedCategoryNode> nodes) {
        for (final node in nodes) {
          ids.add(node.id);
          walk(node.children);
        }
      }

      walk(defaultCategoryTree(en));
      expect(ids, isNot(contains(SystemCategoryIds.uncategorized)));
    });

    test('carries both expense and income categories', () {
      final roots = defaultCategoryTree(en);
      expect(roots.any((n) => n.kind == 'income'), isTrue,
          reason: 'income entry uses the same flow and needs somewhere to go');
      expect(roots.any((n) => n.kind == 'expense'), isTrue);
    });

    test('English and Persian trees have identical structure', () {
      // Only the names differ. A structural divergence would mean a Persian
      // user and an English user get different apps.
      String shape(List<SeedCategoryNode> nodes) => nodes
          .map((n) => '${n.id}:${n.kind}(${shape(n.children)})')
          .join(',');
      expect(shape(defaultCategoryTree(fa)), shape(defaultCategoryTree(en)));
    });

    test('every name is actually translated', () {
      final enNames = <String>[];
      final faNames = <String>[];
      void walk(List<SeedCategoryNode> nodes, List<String> into) {
        for (final node in nodes) {
          into.add(node.name);
          walk(node.children, into);
        }
      }

      walk(defaultCategoryTree(en), enNames);
      walk(defaultCategoryTree(fa), faNames);
      for (var i = 0; i < enNames.length; i++) {
        expect(faNames[i], isNot(enNames[i]),
            reason: '"${enNames[i]}" is identical in both bundles, which means '
                'the fa translation was never written');
      }
    });
  });
}
