import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/tag_repository.dart';

/// Opens the create/edit sheet for a tag.
Future<void> showTagEditorSheet(
  BuildContext context, {
  required TagRepository repository,
  Tag? tag,
  String? parentId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TagEditorSheet(
        repository: repository,
        tag: tag,
        parentId: parentId,
      ),
    );

class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({
    super.key,
    required this.repository,
    this.tag,
    this.parentId,
  });

  final TagRepository repository;
  final Tag? tag;
  final String? parentId;

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.tag?.name ?? '');
  late String _iconKey = widget.tag?.iconKey ?? 'tag';
  late int _color = widget.tag?.color ?? NimbusColors.defaultSwatch.toARGB32();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final existing = widget.tag;
    final name = _name.text.trim();

    if (existing == null) {
      if (name.isEmpty) return;
      // findOrCreate rather than create: someone typing a name that already
      // exists means that tag, and a second row would split its history.
      await widget.repository.findOrCreate(name, parentId: widget.parentId);
    } else {
      if (name.isNotEmpty && name != existing.name) {
        await widget.repository.rename(existing.id, name);
      }
      if (_iconKey != existing.iconKey || _color != existing.color) {
        await widget.repository
            .updateAppearance(existing.id, iconKey: _iconKey, color: _color);
      }
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.tag == null ? l10n.tagNewTitle : l10n.tagEditTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('tag-name-field'),
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.tagNameLabel,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: NimbusTokens.space4),
            IconPicker(
              selected: _iconKey,
              semanticsLabel: l10n.categoryIconLabel,
              onSelected: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: NimbusTokens.space4),
            ColorPicker(
              selected: _color,
              semanticsLabel: l10n.categoryColorLabel,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: NimbusTokens.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: NimbusTokens.space2),
                FilledButton(
                  key: const Key('tag-save'),
                  onPressed: _save,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
