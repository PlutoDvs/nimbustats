import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Normalises digits and regroups the amount as it is typed.
///
/// Order matters. Persian and Arabic-Indic input is folded to Latin *first*,
/// so nothing downstream ever sees a codepoint it does not understand -- a
/// user typing ۱۲۳۴۵ is typing 12345, not a parse error.
///
/// A value that does not parse is left exactly as typed. `1.` is a normal
/// intermediate state on the way to `1.5`, and rewriting or rejecting it
/// mid-keystroke would make the field fight the user. Validation happens once,
/// on save.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter(this.formatter);

  final MoneyFormatter formatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final latin = Digits.toLatin(newValue.text);
    final buffer = StringBuffer();
    for (var i = 0; i < latin.length; i++) {
      final char = latin[i];
      final code = char.codeUnitAt(0);
      final isDigit = code >= 0x30 && code <= 0x39;
      // Group separators are dropped rather than preserved: they are display,
      // and this rebuilds them from the parsed value every keystroke.
      if (isDigit || char == '.' || (char == '-' && buffer.isEmpty)) {
        buffer.write(char);
      }
    }

    final raw = buffer.toString();
    if (raw.isEmpty) return const TextEditingValue();

    final money = formatter.parse(raw);
    final text = money == null ? raw : formatter.format(money);
    return TextEditingValue(
      text: text,
      // Caret at the end in both directions. Regrouping changes the string
      // length, so any other offset would jump somewhere arbitrary.
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The amount input. The first thing on the screen and the only required field.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.formatter,
    required this.label,
    this.errorText,
    required this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final MoneyFormatter formatter;
  final String label;
  final String? errorText;

  /// Fires with the *formatted* text. The controller stores it verbatim and
  /// parses once at save; MoneyFormatter.parse strips the group separators, so
  /// there is no second representation to keep in sync.
  final ValueChanged<String> onChanged;

  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      key: const Key('tx-amount-field'),
      controller: controller,
      focusNode: focusNode,
      // The keypad must be up before the user decides what to do, which is
      // half of what makes a five-second capture possible.
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: theme.textTheme.displaySmall,
      inputFormatters: [AmountInputFormatter(formatter)],
      decoration: InputDecoration(
        labelText: label,
        // `error` rather than `errorText` so the message can carry a key. It
        // still lands in the field's error slot, so a screen reader announces
        // it as the field's error rather than as loose text underneath.
        error: errorText == null
            ? null
            : Text(
                errorText!,
                key: const Key('tx-amount-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NimbusTokens.space4,
          vertical: NimbusTokens.space4,
        ),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted?.call(),
    );
  }
}
