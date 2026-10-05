import 'package:flutter/material.dart';
import '../colors.dart';
import '../tokens.dart';

/// The single place a stored icon key becomes an [IconData].
///
/// Shared by categories and tags, which both persist icon keys. Two maps would
/// mean the same key rendering differently depending on which screen you were
/// looking at.
///
/// Icon keys are persisted, so they arrive from three directions that must all
/// resolve identically: first-run seeding, a Phase 2 merchant rule, and a
/// backup restored onto a different build. One map is what makes that true.
///
/// Const `IconData` only -- these are all tree-shakeable constants, which is
/// why the map is a literal rather than something built at runtime.
const nimbusIcons = <String, IconData>{
  'tag': Icons.label_outline,
  'restaurant': Icons.restaurant,
  'restaurant_menu': Icons.restaurant_menu,
  'shopping_basket': Icons.shopping_basket_outlined,
  'local_cafe': Icons.local_cafe_outlined,
  'directions_bus': Icons.directions_bus_outlined,
  'local_gas_station': Icons.local_gas_station_outlined,
  'local_taxi': Icons.local_taxi_outlined,
  'directions_transit': Icons.directions_transit_outlined,
  'home': Icons.home_outlined,
  'vpn_key': Icons.vpn_key_outlined,
  'bolt': Icons.bolt_outlined,
  'wifi': Icons.wifi,
  'favorite': Icons.favorite_outline,
  'medication': Icons.medication_outlined,
  'medical_services': Icons.medical_services_outlined,
  'shopping_bag': Icons.shopping_bag_outlined,
  'checkroom': Icons.checkroom_outlined,
  'devices': Icons.devices_outlined,
  'movie': Icons.movie_outlined,
  'school': Icons.school_outlined,
  'card_giftcard': Icons.card_giftcard_outlined,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments_outlined,
  // The default Card payment method's glyph. Before it existed, a card could
  // only borrow the cash or gift-card icon.
  'credit_card': Icons.credit_card_outlined,
  'work': Icons.work_outline,
  'savings': Icons.savings_outlined,
  'help_outline': Icons.help_outline,
  // Habit trackers' glyphs (Phase 4). The presets use the first four.
  'water_drop': Icons.water_drop_outlined,
  'smoking_rooms': Icons.smoking_rooms_outlined,
  'fitness_center': Icons.fitness_center_outlined,
  'bedtime': Icons.bedtime_outlined,
  'self_improvement': Icons.self_improvement_outlined,
  'menu_book': Icons.menu_book_outlined,
  'directions_run': Icons.directions_run_outlined,
  'timer': Icons.timer_outlined,
};

/// Resolves a stored key, falling back rather than throwing.
///
/// An icon is cosmetic. A key this build does not know about -- from a newer
/// version's backup, say -- must not take the category manager down, so this
/// degrades to a neutral glyph and the row still renders its name and its
/// actions.
IconData nimbusIconFor(String key) =>
    nimbusIcons[key] ?? Icons.label_outline;

/// A wrapping grid of selectable icons.
class IconPicker extends StatelessWidget {
  const IconPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.semanticsLabel,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  /// Localized name of the field, e.g. "Icon". Resolved by the caller because
  /// this package's design tokens carry no ARB bundle.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Wrap(
        spacing: NimbusTokens.space2,
        runSpacing: NimbusTokens.space2,
        children: [
          for (final entry in nimbusIcons.entries)
            IconButton(
              key: Key('icon-option-${entry.key}'),
              icon: Icon(entry.value),
              tooltip: entry.key,
              isSelected: entry.key == selected,
              color: entry.key == selected ? scheme.primary : scheme.onSurface,
              onPressed: () => onSelected(entry.key),
            ),
        ],
      ),
    );
  }
}

/// A wrapping row of the named category swatches.
class ColorPicker extends StatelessWidget {
  const ColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.semanticsLabel,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Wrap(
        spacing: NimbusTokens.space2,
        runSpacing: NimbusTokens.space2,
        children: [
          for (final entry in NimbusColors.categorySwatches.entries)
            _Swatch(
              key: Key('color-option-${entry.key}'),
              color: entry.value,
              name: entry.key,
              isSelected: entry.value.toARGB32() == selected,
              outline: scheme.onSurface,
              onTap: () => onSelected(entry.value.toARGB32()),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.color,
    required this.name,
    required this.isSelected,
    required this.outline,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool isSelected;
  final Color outline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: name,
        selected: isSelected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: NimbusTokens.borderRadiusSm,
          child: SizedBox(
            // The floor applies to a colour swatch as much as to a button: it
            // is the smallest thing on this sheet and the easiest to miss.
            width: NimbusTokens.minTapTarget,
            height: NimbusTokens.minTapTarget,
            child: Center(
              child: Container(
                width: NimbusTokens.space6,
                height: NimbusTokens.space6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: outline, width: 2)
                      : null,
                ),
              ),
            ),
          ),
        ),
      );
}
