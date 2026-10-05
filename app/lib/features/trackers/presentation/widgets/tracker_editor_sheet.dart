import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../data/tracker_draft.dart';
import '../../data/tracker_repository.dart';
import 'tracker_write.dart';

/// Localised name for a [TrackerType]. It lives here rather than on the enum
/// because `nimbus_domain` has no ARB bundle.
String trackerTypeLabel(AppLocalizations l10n, TrackerType type) =>
    switch (type) {
      TrackerType.counter => l10n.trackerTypeCounter,
      TrackerType.boolean => l10n.trackerTypeBoolean,
      TrackerType.quantity => l10n.trackerTypeQuantity,
      TrackerType.duration => l10n.trackerTypeDuration,
    };

/// Opens the create/edit sheet for a tracker.
///
/// Resolves to the tracker just created. It is null when the sheet was
/// dismissed or an existing tracker was edited.
Future<Tracker?> showTrackerEditorSheet(
  BuildContext context, {
  required TrackerRepository repository,
  Tracker? tracker,
}) {
  // A snackbar left from the last action would float over the sheet's Save.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<Tracker>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        TrackerEditorSheet(repository: repository, tracker: tracker),
  );
}

class TrackerEditorSheet extends ConsumerStatefulWidget {
  const TrackerEditorSheet({super.key, required this.repository, this.tracker});

  final TrackerRepository repository;
  final Tracker? tracker;

  @override
  ConsumerState<TrackerEditorSheet> createState() => _TrackerEditorSheetState();
}

class _TrackerEditorSheetState extends ConsumerState<TrackerEditorSheet> {
  late final _name = TextEditingController(text: widget.tracker?.name ?? '');
  late final _unit = TextEditingController(text: widget.tracker?.unit ?? '');
  // In the user's digits, which parseAmount reads back.
  late final _perTap = TextEditingController(
      text: switch (widget.tracker?.perTapValue) {
        final value? => ref.read(trackerFormatProvider).number(value),
        null => '',
      });
  late TrackerType _type = widget.tracker?.type ?? TrackerType.counter;
  late String _iconKey = widget.tracker?.iconKey ?? 'tag';
  late int _color =
      widget.tracker?.color ?? NimbusColors.defaultSwatch.toARGB32();

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _perTap.dispose();
    super.dispose();
  }

  /// Whether the per-tap field was typed in. Until it is, the stored amount
  /// is kept as it is: the field shows two decimals, so 0.125 reads "0.13",
  /// and writing that text back on a rename would change the amount.
  bool _perTapEdited = false;

  double? get _perTapValue => TrackerValues.parseAmount(_perTap.text);

  bool get _isQuantity => _type == TrackerType.quantity;

  /// Save stays disabled until the tracker is complete. The repository throws
  /// on a bad definition, which is right for a programming error and wrong as
  /// the way to tell a user a field is empty.
  bool get _canSave =>
      _name.text.trim().isNotEmpty && (!_isQuantity || _perTapValue != null);

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = _isQuantity ? _unit.text : null;
    final stored = widget.tracker?.perTapValue;
    final perTap = !_isQuantity
        ? null
        : (_perTapEdited || stored == null ? _perTapValue : stored);

    final existing = widget.tracker;
    if (existing == null) {
      final created = await reportingTrackerFailure(
        messenger: messenger,
        l10n: l10n,
        write: () => widget.repository.create(TrackerDraft(
          name: _name.text,
          iconKey: _iconKey,
          color: _color,
          type: _type,
          unit: unit,
          perTapValue: perTap,
        )),
      );
      navigator.pop(created);
      return;
    }
    await reportingTrackerFailure(
      messenger: messenger,
      l10n: l10n,
      write: () => widget.repository.update(
        existing.id,
        name: _name.text,
        iconKey: _iconKey,
        color: _color,
        unit: unit,
        perTapValue: perTap,
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final perTapInvalid = _perTap.text.trim().isNotEmpty && _perTapValue == null;

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
            Text(widget.tracker == null ? l10n.trackerNew : l10n.trackerEditTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('tracker-name-field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.trackerNameLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NimbusTokens.space4),
            if (widget.tracker == null)
              Semantics(
                label: l10n.trackerTypeLabel,
                container: true,
                // Chips that wrap rather than a segmented button: four labels
                // in Persian at a large font scale do not fit one row.
                child: Wrap(
                  spacing: NimbusTokens.space2,
                  runSpacing: NimbusTokens.space2,
                  children: [
                    for (final type in TrackerType.values)
                      ChoiceChip(
                        key: Key('tracker-type-${type.name}'),
                        label: Text(trackerTypeLabel(l10n, type)),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
              )
            else
              ListTile(
                key: const Key('tracker-type-fixed'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.trackerTypeLabel),
                subtitle: Text(
                    '${trackerTypeLabel(l10n, _type)} · ${l10n.trackerTypeFixedHint}'),
              ),
            if (_isQuantity) ...[
              const SizedBox(height: NimbusTokens.space4),
              TextField(
                key: const Key('tracker-per-tap-field'),
                controller: _perTap,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.trackerPerTapLabel,
                  errorText: perTapInvalid ? l10n.trackerAmountInvalid : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _perTapEdited = true),
              ),
              const SizedBox(height: NimbusTokens.space4),
              TextField(
                key: const Key('tracker-unit-field'),
                controller: _unit,
                decoration: InputDecoration(
                  labelText: l10n.trackerUnitLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
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
                  key: const Key('tracker-save'),
                  onPressed: _canSave ? _save : null,
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
