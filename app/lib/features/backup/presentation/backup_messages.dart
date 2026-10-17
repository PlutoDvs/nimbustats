import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';

/// The message for a backup error the user can act on (spec §5.4), or null
/// for one no message names. The caller reports a null case and shows its
/// generic failure text.
String? backupErrorText(AppLocalizations l10n, Object error) => switch (error) {
      NotABackup() => l10n.backupNotABackup,
      UnsupportedFormat() => l10n.backupUnsupported,
      NewerSchema() => l10n.backupNewerSchema,
      WrongPassphrase() => l10n.backupWrongPassphrase,
      CorruptBackup() => l10n.backupCorrupt,
      _ => null,
    };

/// Reports an error no message names, under `backup`. Callers pass the
/// error, never the passphrase.
void reportBackupFailure(Object error, StackTrace stack, String context) =>
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'backup',
      context: ErrorDescription(context),
    ));

/// A moment as `yyyy/MM/dd HH:mm`, in the local zone, the active calendar
/// and the user's digits: the way the transaction list writes a day.
String whenLabel(DateTime moment, AppCalendar calendar,
    {required bool persianDigits}) {
  final local = moment.toLocal();
  final parts = calendar.partsOf(DateKey.fromDateTime(local));
  String two(int value) => value.toString().padLeft(2, '0');
  final text = '${parts.year}/${two(parts.month)}/${two(parts.day)} '
      '${two(local.hour)}:${two(local.minute)}';
  return persianDigits ? Digits.toPersian(text) : text;
}
