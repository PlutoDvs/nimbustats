import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';

/// The category tree seeded on first run.
///
/// Zero-config first run is a stated requirement: nobody should have to build
/// a taxonomy before logging their first expense. This is deliberately broad
/// rather than deep -- two levels, common cases only. A tree that tries to
/// anticipate everything is worse than one the user prunes in ten seconds.
///
/// Ids are fixed strings and must never change. A Phase 2 merchant rule points
/// at `seed-food-coffee`, and a backup restored onto a fresh install has to
/// land on the same node.
///
/// Names come from the ARB bundles; `nimbus_data` cannot localize, so the tree
/// is fully resolved before it crosses that boundary.
List<SeedCategoryNode> defaultCategoryTree(AppLocalizations l10n) {
  int swatch(String name) => NimbusColors.swatch(name).toARGB32();

  return [
    SeedCategoryNode(
      id: 'seed-food',
      name: l10n.seedCategoryFood,
      iconKey: 'restaurant',
      color: swatch('orange'),
      children: [
        SeedCategoryNode(
          id: 'seed-food-groceries',
          name: l10n.seedCategoryFoodGroceries,
          iconKey: 'shopping_basket',
          color: swatch('orange'),
        ),
        SeedCategoryNode(
          id: 'seed-food-dining',
          name: l10n.seedCategoryFoodDining,
          iconKey: 'restaurant_menu',
          color: swatch('orange'),
        ),
        SeedCategoryNode(
          id: 'seed-food-coffee',
          name: l10n.seedCategoryFoodCoffee,
          iconKey: 'local_cafe',
          color: swatch('brown'),
        ),
      ],
    ),
    SeedCategoryNode(
      id: 'seed-transport',
      name: l10n.seedCategoryTransport,
      iconKey: 'directions_bus',
      color: swatch('blue'),
      children: [
        SeedCategoryNode(
          id: 'seed-transport-fuel',
          name: l10n.seedCategoryTransportFuel,
          iconKey: 'local_gas_station',
          color: swatch('blue'),
        ),
        SeedCategoryNode(
          id: 'seed-transport-taxi',
          name: l10n.seedCategoryTransportTaxi,
          iconKey: 'local_taxi',
          color: swatch('amber'),
        ),
        SeedCategoryNode(
          id: 'seed-transport-public',
          name: l10n.seedCategoryTransportPublic,
          iconKey: 'directions_transit',
          color: swatch('blue'),
        ),
      ],
    ),
    SeedCategoryNode(
      id: 'seed-home',
      name: l10n.seedCategoryHome,
      iconKey: 'home',
      color: swatch('purple'),
      children: [
        SeedCategoryNode(
          id: 'seed-home-rent',
          name: l10n.seedCategoryHomeRent,
          iconKey: 'vpn_key',
          color: swatch('purple'),
        ),
        SeedCategoryNode(
          id: 'seed-home-utilities',
          name: l10n.seedCategoryHomeUtilities,
          iconKey: 'bolt',
          color: swatch('purple'),
        ),
        SeedCategoryNode(
          id: 'seed-home-internet',
          name: l10n.seedCategoryHomeInternet,
          iconKey: 'wifi',
          color: swatch('purple'),
        ),
      ],
    ),
    SeedCategoryNode(
      id: 'seed-health',
      name: l10n.seedCategoryHealth,
      iconKey: 'favorite',
      color: swatch('pink'),
      children: [
        SeedCategoryNode(
          id: 'seed-health-pharmacy',
          name: l10n.seedCategoryHealthPharmacy,
          iconKey: 'medication',
          color: swatch('pink'),
        ),
        SeedCategoryNode(
          id: 'seed-health-doctor',
          name: l10n.seedCategoryHealthDoctor,
          iconKey: 'medical_services',
          color: swatch('pink'),
        ),
      ],
    ),
    SeedCategoryNode(
      id: 'seed-shopping',
      name: l10n.seedCategoryShopping,
      iconKey: 'shopping_bag',
      color: swatch('teal'),
      children: [
        SeedCategoryNode(
          id: 'seed-shopping-clothing',
          name: l10n.seedCategoryShoppingClothing,
          iconKey: 'checkroom',
          color: swatch('teal'),
        ),
        SeedCategoryNode(
          id: 'seed-shopping-electronics',
          name: l10n.seedCategoryShoppingElectronics,
          iconKey: 'devices',
          color: swatch('teal'),
        ),
      ],
    ),
    SeedCategoryNode(
      id: 'seed-entertainment',
      name: l10n.seedCategoryEntertainment,
      iconKey: 'movie',
      color: swatch('indigo'),
    ),
    SeedCategoryNode(
      id: 'seed-education',
      name: l10n.seedCategoryEducation,
      iconKey: 'school',
      color: swatch('green'),
    ),
    SeedCategoryNode(
      id: 'seed-gifts',
      name: l10n.seedCategoryGifts,
      iconKey: 'card_giftcard',
      color: swatch('pink'),
    ),
    SeedCategoryNode(
      id: 'seed-other',
      name: l10n.seedCategoryOther,
      iconKey: 'more_horiz',
      color: swatch('slate'),
    ),
    // Income shares the same flow and the same tree, distinguished by `kind`.
    SeedCategoryNode(
      id: 'seed-salary',
      name: l10n.seedCategorySalary,
      iconKey: 'payments',
      color: swatch('green'),
      kind: 'income',
    ),
    SeedCategoryNode(
      id: 'seed-freelance',
      name: l10n.seedCategoryFreelance,
      iconKey: 'work',
      color: swatch('green'),
      kind: 'income',
    ),
    SeedCategoryNode(
      id: 'seed-other-income',
      name: l10n.seedCategoryOtherIncome,
      iconKey: 'savings',
      color: swatch('green'),
      kind: 'income',
    ),
  ];
}
