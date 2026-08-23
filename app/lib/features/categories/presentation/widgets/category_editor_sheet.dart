import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/category_repository.dart';
import 'icon_picker.dart';

/// Opens the create/edit sheet.
///
/// One sheet for both, because they differ only in which fields start filled.
/// [category] null means create; [parentId] is where a newly created node
/// lands.
Future<void> showCategoryEditorSheet(
  BuildContext context, {
  required CategoryRepository repository,
  Category? category,
  String? parentId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      // The sheet grows a keyboard and two wrapping pickers, so it has to be
      // free to take more than half the screen rather than clipping.
      isScrollControlled: true,
      builder: (context) => CategoryEditorSheet(
        repository: repository,
        category: category,
        parentId: parentId,
      ),
    );

class CategoryEditorSheet extends StatefulWidget {
  const CategoryEditorSheet({
    super.key,
    required this.repository,
    this.category,
    this.parentId,
  });

  final CategoryRepository repository;
  final Category? category;
  final String? parentId;

  @override
  State<CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<CategoryEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.category?.name ?? '');
  late String _iconKey = widget.category?.iconKey ?? 'tag';
  late int _color =
      widget.category?.color ?? NimbusColors.defaultSwatch.toARGB32();

  /// The system row can be recoloured but not renamed, so the field is
  /// disabled rather than left to fail on save. The repository still guards
  /// it; this is what stops the UI from offering the attempt.
  bool get _nameEditable =>
      widget.category == null ||
      !SystemCategoryIds.isSystem(widget.category!.id);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final existing = widget.category;
    final name = _name.text.trim();

    if (existing == null) {
      if (name.isEmpty) return;
      await widget.repository.create(
        name: name,
        parentId: widget.parentId,
        iconKey: _iconKey,
        color: _color,
      );
    } else {
      if (_nameEditable && name.isNotEmpty && name != existing.name) {
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
              widget.category == null
                  ? l10n.categoryNewTitle
                  : l10n.categoryEditTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('category-name-field'),
              controller: _name,
              enabled: _nameEditable,
              autofocus: _nameEditable,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.categoryNameLabel,
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
                  key: const Key('category-save'),
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
