import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// Asks for a saved view's name. Returns it trimmed, or null if dismissed.
///
/// One sheet for pinning and renaming: they ask the same question, and two
/// copies would drift apart on what counts as a valid name.
Future<String?> showViewNameSheet(
  BuildContext context, {
  required String title,
  required String initialName,
  String? note,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ViewNameSheet(
        title: title,
        initialName: initialName,
        note: note,
      ),
    );

class _ViewNameSheet extends StatefulWidget {
  const _ViewNameSheet({
    required this.title,
    required this.initialName,
    this.note,
  });

  final String title;
  final String initialName;
  final String? note;

  @override
  State<_ViewNameSheet> createState() => _ViewNameSheetState();
}

class _ViewNameSheetState extends State<_ViewNameSheet> {
  late final _name = TextEditingController(text: widget.initialName);

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
