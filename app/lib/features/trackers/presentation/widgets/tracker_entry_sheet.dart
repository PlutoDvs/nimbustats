import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';
import 'tracker_duration_fields.dart';
import 'tracker_write.dart';

/// Edits one entry: its time and note always, its amount for a quantity, its
/// length for a timed session. Counter and boolean values are fixed at 1.
Future<void> showTrackerEntrySheet(
  BuildContext context, {
  required Tracker tracker,
  required TrackerEntry entry,
}) {
  // A snackbar left from the last action would float over the sheet's Save.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EntrySheet(tracker: tracker, entry: entry),
  );
}

class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({required this.tracker, required this.entry});

  final Tracker tracker;
  final TrackerEntry entry;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  late final TrackerFormat _format = ref.read(trackerFormatProvider);
  late DateTime _wall =
      ref.read(trackerClockProvider).toLocal(widget.entry.occurredAtUtc);

  /// Whether a date or time was picked. Until one is, the stored instant is
  /// passed through untouched, so the entry keeps the day it was logged on.
  /// Rebuilding it from the wall time would drop its seconds and re-derive
  /// the day where the device is now.
  bool _timeChanged = false;

  /// Likewise for the value. A timed session's seconds and an amount's third
  /// decimal survive an edit that never touched them.
  bool _valueEdited = false;

  late final _note = TextEditingController(text: widget.entry.note ?? '');
  late final _amount = TextEditingController(
      text: _isQuantity ? _format.number(widget.entry.value) : '');
  late final Duration _length = TrackerValues.durationOf(widget.entry.value);
  late final _hours =
      TextEditingController(text: _isDuration ? _digits(_length.inHours) : '');
  late final _minutes = TextEditingController(
      text: _isDuration ? _digits(_length.inMinutes % 60) : '');
  String? _valueError;
  String? _dayError;

  bool get _isQuantity => widget.tracker.type == TrackerType.quantity;
  bool get _isDuration => widget.tracker.type == TrackerType.duration;

  String _digits(int value) =>
      _format.persianDigits ? Digits.toPersian('$value') : '$value';

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _valueChanged(String _) => setState(() {
        _valueEdited = true;
        _valueError = null;
      });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _wall,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _wall = DateTime(
          picked.year, picked.month, picked.day, _wall.hour, _wall.minute);
      _timeChanged = true;
      _dayError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _wall = DateTime(
          _wall.year, _wall.month, _wall.day, picked.hour, picked.minute);
      _timeChanged = true;
      _dayError = null;
    });
  }

  double? _value() {
    if (!_valueEdited) return widget.entry.value;
    if (_isQuantity) return TrackerValues.parseAmount(_amount.text);
    if (_isDuration) {
      final length = TrackerDurationFields.read(_hours, _minutes);
      return length == null ? null : TrackerValues.secondsOf(length);
    }
    return widget.entry.value;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final value = _value();
    if (value == null) {
      setState(() => _valueError = _isDuration
          ? l10n.trackerDurationInvalid
          : l10n.trackerAmountInvalid);
      return;
    }
    final navigator = Navigator.of(context);
    final clock = ref.read(trackerClockProvider);
    final repository = ref.read(trackerRepositoryProvider);
    final entry = widget.entry;

    final result = await reportingTrackerFailure(
      messenger: ScaffoldMessenger.of(context),
      l10n: l10n,
      write: () => repository.updateEntry(TrackerEntry(
        id: entry.id,
        trackerId: entry.trackerId,
        value: value,
        occurredAtUtc:
            _timeChanged ? clock.fromLocal(_wall) : entry.occurredAtUtc,
        // The repository re-derives it when the time changed.
        localDateKey: entry.localDateKey,
        note: _note.text,
      )),
    );
    if (!mounted) return;
    switch (result) {
      case DayWrite.written:
        navigator.pop();
      case DayWrite.dayAlreadyDone:
        setState(() => _dayError = l10n.trackerDayAlreadyDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final day =
        _timeChanged ? DateKey.fromDateTime(_wall) : widget.entry.localDateKey;

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
            Text(l10n.trackerEntryEditTitle, style: theme.textTheme.titleMedium),
            ListTile(
              key: const Key('tracker-entry-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.trackerEntryDateLabel),
              trailing: Text(_format.date(day)),
              onTap: _pickDate,
            ),
            ListTile(
              key: const Key('tracker-entry-time'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.trackerEntryTimeLabel),
              trailing: Text(_format.time(_wall)),
              onTap: _pickTime,
            ),
            if (_isQuantity) ...[
              const SizedBox(height: NimbusTokens.space2),
              TextField(
                key: const Key('tracker-entry-amount'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.trackerAmountLabel,
                  suffixText: widget.tracker.unit,
                  errorText: _valueError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _valueChanged,
              ),
            ],
            if (_isDuration) ...[
              const SizedBox(height: NimbusTokens.space2),
              TrackerDurationFields(
                hours: _hours,
                minutes: _minutes,
                keyPrefix: 'tracker-entry',
                errorText: _valueError,
                onChanged: _valueChanged,
              ),
            ],
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('tracker-entry-note'),
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.trackerEntryNoteLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_dayError != null) ...[
              const SizedBox(height: NimbusTokens.space2),
              Text(
                _dayError!,
                key: const Key('tracker-entry-day-error'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
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
                  key: const Key('tracker-entry-save'),
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
