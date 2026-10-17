import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

/// The frame both backup sheets share: clear of the keyboard, a title, then
/// the rows.
class BackupSheetFrame extends StatelessWidget {
  const BackupSheetFrame({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        // The fields sit at the bottom of the screen, and would otherwise sit
        // under the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: NimbusTokens.space3,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                ...children,
              ],
            ),
          ),
        ),
      );
}

/// A passphrase input. It is hidden and has no suggestions or autocorrect, so
/// the keyboard neither shows it nor learns it.
class PassphraseField extends StatelessWidget {
  const PassphraseField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.error,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
        ),
      );
}

/// Real work in progress, named once for screen readers.
class BackupProgress extends StatelessWidget {
  const BackupProgress({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NimbusTokens.space2,
        children: [
          LinearProgressIndicator(semanticsLabel: label),
          ExcludeSemantics(child: Text(label)),
        ],
      );
}
