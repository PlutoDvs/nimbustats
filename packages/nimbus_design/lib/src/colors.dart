import 'package:flutter/material.dart';

/// Colours the app needs that Material's [ColorScheme] has no slot for.
///
/// Direction (expense vs income) and the two reflection axes are domain
/// concepts, not Material roles, so they live in a [ThemeExtension] rather than
/// being smuggled into `tertiary` and friends where the next reader would have
/// to guess what the slot meant.
@immutable
final class NimbusSemanticColors extends ThemeExtension<NimbusSemanticColors> {
  const NimbusSemanticColors({
    required this.expense,
    required this.income,
    required this.necessityNeeded,
    required this.necessityOptional,
    required this.necessityAvoidable,
    required this.satisfactionGlad,
    required this.satisfactionNeutral,
    required this.satisfactionRegret,
    required this.skeleton,
  });

  final Color expense;
  final Color income;
  final Color necessityNeeded;
  final Color necessityOptional;
  final Color necessityAvoidable;
  final Color satisfactionGlad;
  final Color satisfactionNeutral;
  final Color satisfactionRegret;

  /// Fill for loading skeleton rows.
  final Color skeleton;

  static NimbusSemanticColors of(BuildContext context) {
    final ext = Theme.of(context).extension<NimbusSemanticColors>();
    if (ext == null) {
      // Not a fallback: a missing extension means the app was built without
      // NimbusTheme, and returning defaults here would hide that until someone
      // noticed the wrong red in a screenshot.
      throw StateError(
        'NimbusSemanticColors is missing. Build the app with NimbusTheme.',
      );
    }
    return ext;
  }

  @override
  NimbusSemanticColors copyWith({
    Color? expense,
    Color? income,
    Color? necessityNeeded,
    Color? necessityOptional,
    Color? necessityAvoidable,
    Color? satisfactionGlad,
    Color? satisfactionNeutral,
    Color? satisfactionRegret,
    Color? skeleton,
  }) =>
      NimbusSemanticColors(
        expense: expense ?? this.expense,
        income: income ?? this.income,
        necessityNeeded: necessityNeeded ?? this.necessityNeeded,
        necessityOptional: necessityOptional ?? this.necessityOptional,
        necessityAvoidable: necessityAvoidable ?? this.necessityAvoidable,
        satisfactionGlad: satisfactionGlad ?? this.satisfactionGlad,
        satisfactionNeutral: satisfactionNeutral ?? this.satisfactionNeutral,
        satisfactionRegret: satisfactionRegret ?? this.satisfactionRegret,
        skeleton: skeleton ?? this.skeleton,
      );

  @override
  NimbusSemanticColors lerp(
    ThemeExtension<NimbusSemanticColors>? other,
    double t,
  ) {
    if (other is! NimbusSemanticColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NimbusSemanticColors(
      expense: mix(expense, other.expense),
      income: mix(income, other.income),
      necessityNeeded: mix(necessityNeeded, other.necessityNeeded),
      necessityOptional: mix(necessityOptional, other.necessityOptional),
      necessityAvoidable: mix(necessityAvoidable, other.necessityAvoidable),
      satisfactionGlad: mix(satisfactionGlad, other.satisfactionGlad),
      satisfactionNeutral: mix(satisfactionNeutral, other.satisfactionNeutral),
      satisfactionRegret: mix(satisfactionRegret, other.satisfactionRegret),
      skeleton: mix(skeleton, other.skeleton),
    );
  }
}

/// PROVISIONAL palette, derived from the screen contract rather than a design
/// token sheet.
///
/// Every value below is checked against WCAG AA by `test/theme_test.dart`, so a
/// future substitution cannot quietly become unreadable.
abstract final class NimbusColors {
  /// A muted green. Money apps that shout at you get uninstalled, and the
  /// regret matrix in Phase 3 is explicitly required to read as factual rather
  /// than punitive -- which starts with the seed, not with that screen.
  static const seed = Color(0xFF2E7D64);

  static final ColorScheme lightScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

  static final ColorScheme darkScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

  // The green is deliberately much darker than the red rather than its
  // mirror-image in hue. A 2E7D64-style green and a C0392B red sit at almost
  // identical relative luminance, which is exactly the pair a red-green
  // colourblind user cannot separate -- and a ledger where income and expense
  // look the same is worse than one with no colour at all. The luminance gap is
  // asserted in test/theme_test.dart so a future palette cannot lose it.
  static const lightSemantics = NimbusSemanticColors(
    expense: Color(0xFFC0392B),
    income: Color(0xFF0F5C42),
    necessityNeeded: Color(0xFF0F5C42),
    necessityOptional: Color(0xFF8A6A00),
    necessityAvoidable: Color(0xFFC0392B),
    satisfactionGlad: Color(0xFF0F5C42),
    satisfactionNeutral: Color(0xFF5A5F5C),
    satisfactionRegret: Color(0xFFC0392B),
    skeleton: Color(0xFFE3E7E4),
  );

  /// The palette a category, tag, or payment method can be tinted with.
  ///
  /// Named rather than free-form so the colour picker, the seeded default
  /// tree, and any future import all draw from one set -- and so no screen
  /// ever holds a raw hex literal, which `app/test/ux_rules_test.dart`
  /// enforces.
  ///
  /// PROVISIONAL, like the rest of this file. These are mid-tone hues chosen
  /// to stay distinguishable from each other on both surfaces; a real token
  /// sheet should replace them wholesale.
  static const categorySwatches = <String, Color>{
    'orange': Color(0xFFEF6C00),
    'blue': Color(0xFF1565C0),
    'purple': Color(0xFF6A1B9A),
    'pink': Color(0xFFC2185B),
    'teal': Color(0xFF00838F),
    'indigo': Color(0xFF4527A0),
    'green': Color(0xFF2E7D32),
    'slate': Color(0xFF546E7A),
    'brown': Color(0xFF6D4C41),
    'amber': Color(0xFF8A6A00),
  };

  /// Fallback tint for a node whose colour was never set.
  static const defaultSwatch = Color(0xFF9E9E9E);

  static Color swatch(String name) =>
      categorySwatches[name] ?? defaultSwatch;

  static const darkSemantics = NimbusSemanticColors(
    expense: Color(0xFFFF8A80),
    income: Color(0xFF6EE7B7),
    necessityNeeded: Color(0xFF6EE7B7),
    necessityOptional: Color(0xFFE8C547),
    necessityAvoidable: Color(0xFFFF8A80),
    satisfactionGlad: Color(0xFF6EE7B7),
    satisfactionNeutral: Color(0xFFA8B0AC),
    satisfactionRegret: Color(0xFFFF8A80),
    skeleton: Color(0xFF2A2E2C),
  );
}
