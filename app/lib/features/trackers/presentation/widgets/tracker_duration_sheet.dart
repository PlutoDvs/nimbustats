import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import 'tracker_duration_fields.dart';

/// Asks how long a session lasted, for one the user forgot to time. Resolves
/// to the duration, or null when dismissed.
Future<Duration?> showAddDurationSheet(BuildContext context) {
  // A snackbar left from the last action would float over the sheet's Save.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<Duration>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AddDurationSheet(),
  );
}

class _AddDurationSheet extends StatefulWidget {
  const _AddDurationSheet();

  @override
  State<_AddDurationSheet> createState() => _AddDurationSheetState();
}

class _AddDurationSheetState extends State<_AddDurationSheet> {
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final duration = TrackerDurationFields.read(_hours, _minutes);
    if (duration == null) {
      setState(() =>
          _error = AppLocalizations.of(context).trackerDurationInvalid);
      return;
    }
    Navigator.of(context).pop(duration);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.trackerAddDuration,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NimbusTokens.space4),
          TrackerDurationFields(
            hours: _hours,
            minutes: _minutes,
            keyPrefix: 'tracker-duration',
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
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
                key: const Key('tracker-duration-save'),
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
