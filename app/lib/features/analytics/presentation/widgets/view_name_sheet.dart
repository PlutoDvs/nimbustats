import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// Asks for a saved view's name. Returns it trimmed, or null if dismissed.
///
/// One sheet for pinning and renaming: they ask the same question, and two
/// copies would drift apart on what counts as a valid name.
///
/// [takenNames] are the names other cards already carry. Reusing one is
/// allowed but said out loud: the dashboard is read by its titles, and two
/// that read the same cannot be told apart. Required, so every caller decides
/// which cards count -- a rename must leave out the card being renamed.
Future<String?> showViewNameSheet(
  BuildContext context, {
  required String title,
  required String initialName,
  required Set<String> takenNames,
  String? note,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ViewNameSheet(
        title: title,
        initialName: initialName,
        takenNames: takenNames,
        note: note,
      ),
    );

/// Names compare as a reader sees them: trimmed, as the sheet saves them, and
/// ignoring case.
String _comparable(String name) => name.trim().toLowerCase();

class _ViewNameSheet extends StatefulWidget {
  const _ViewNameSheet({
    required this.title,
    required this.initialName,
    required this.takenNames,
    this.note,
  });

  final String title;
  final String initialName;
  final Set<String> takenNames;
  final String? note;

  @override
  State<_ViewNameSheet> createState() => _ViewNameSheetState();
}

class _ViewNameSheetState extends State<_ViewNameSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  // Normalised once, so a keystroke costs one lookup.
  late final _taken = {for (final n in widget.takenNames) _comparable(n)};

  bool get _nameTaken => _taken.contains(_comparable(_name.text));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final note = widget.note;

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        // Above the keyboard: the name field autofocuses, so the keyboard is
        // up the moment the sheet opens.
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: NimbusTokens.space4),
          TextField(
            key: const Key('view-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.viewNameLabel),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (_nameTaken) ...[
            const SizedBox(height: NimbusTokens.space2),
            // A live region, so a screen reader hears it appear mid-typing
            // rather than only if the user goes looking.
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: theme.colorScheme.tertiary),
                  ),
                  const SizedBox(width: NimbusTokens.space1),
                  // Expanded, so it wraps at large text sizes instead of
                  // overflowing the sheet.
                  Expanded(
                    child: Text(
                      l10n.viewNameTaken,
                      key: const Key('view-name-taken'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.tertiary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: NimbusTokens.space2),
            Text(note, key: const Key('view-name-note'),
                style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: NimbusTokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: NimbusTokens.space2),
              FilledButton(
                key: const Key('view-name-save'),
                // Disabled rather than rejected on tap: the user sees why
                // before trying.
                onPressed: _name.text.trim().isEmpty ? null : _submit,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
