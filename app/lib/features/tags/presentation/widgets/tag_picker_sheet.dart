import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tag_providers.dart';

/// Opens the tag picker, returning the chosen tag ids, or null if dismissed.
Future<Set<String>?> showTagPickerSheet(
  BuildContext context, {
  required Set<String> selected,
}) =>
    showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TagPickerSheet(initialSelection: selected),
    );

/// Search, select, and create tags without leaving the flow.
///
/// Creating inline is the whole point: forcing a trip to the tag manager
/// before a tag can be used is precisely the friction this app exists to
/// remove, so the search field doubles as the create field and the new tag is
/// selected the moment it exists.
class TagPickerSheet extends ConsumerStatefulWidget {
  const TagPickerSheet({super.key, required this.initialSelection});

  final Set<String> initialSelection;

  @override
  ConsumerState<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  late final Set<String> _selected = {...widget.initialSelection};
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createInline() async {
    final name = _query.trim();
    if (name.isEmpty) return;

    final tag = await ref.read(tagRepositoryProvider).findOrCreate(name);
    if (!mounted) return;
    setState(() {
      _selected.add(tag.id);
      _search.clear();
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final options = ref.watch(tagPickerOptionsProvider).value ?? const [];

    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? options
        : options
            .where((t) => t.name.toLowerCase().contains(query))
            .toList();
    // Offered only when the typed name is not already a tag. Comparing folded
    // means "Travel" does not offer to create a second #travel, which is the
    // same rule findOrCreate applies -- the UI must not suggest an action the
    // repository would quietly turn into a no-op.
    final canCreate = query.isNotEmpty &&
        !options.any((t) => t.name.toLowerCase() == query);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(NimbusTokens.space4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.tagPickerTitle,
                        style: theme.textTheme.titleMedium),
                  ),
                  FilledButton(
                    key: const Key('tag-picker-done'),
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(l10n.commonSave),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: NimbusTokens.space4),
              child: TextField(
                key: const Key('tag-picker-search'),
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l10n.tagPickerSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: (_) => _createInline(),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    vertical: NimbusTokens.space2),
                children: [
                  if (canCreate)
                    ListTile(
                      key: const Key('tag-create-inline'),
                      leading: const Icon(Icons.add),
                      title: Text(l10n.tagCreateInline(_query.trim())),
                      onTap: _createInline,
                    ),
                  for (final tag in matches)
                    CheckboxListTile(
                      key: Key('tag-option-${tag.id}'),
                      value: _selected.contains(tag.id),
                      title: Text(tag.name),
                      subtitle: tag.usageCount == 0
                          ? null
                          : Text(l10n.tagUsageCount(tag.usageCount)),
                      secondary: ExcludeSemantics(
                        child: Icon(
                          nimbusIconFor(tag.iconKey),
                          color: Color(tag.color),
                        ),
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected.add(tag.id);
                        } else {
                          _selected.remove(tag.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
