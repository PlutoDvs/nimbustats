import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/backup/presentation/backup_messages.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  test('a moment reads in the active calendar and digits, in local time', () {
    final moment = DateTime(2026, 10, 17, 9, 5); // local
    expect(whenLabel(moment, const GregorianCalendar(), persianDigits: false),
        '2026/10/17 09:05');
    expect(whenLabel(moment, const JalaliCalendar(), persianDigits: true),
        '۱۴۰۵/۰۷/۲۵ ۰۹:۰۵');
    expect(whenLabel(moment.toUtc(), const GregorianCalendar(), persianDigits: false),
        '2026/10/17 09:05');
  });

  test('each backup error has its own message; anything else has none',
      () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final messages = [
      for (final error in const [
        NotABackup(),
        UnsupportedFormat('x'),
        NewerSchema(backup: 41, app: 40),
        WrongPassphrase(),
        CorruptBackup('x'),
      ])
        backupErrorText(l10n, error),
    ];
    expect(messages, [
      l10n.backupNotABackup,
      l10n.backupUnsupported,
      l10n.backupNewerSchema,
      l10n.backupWrongPassphrase,
      l10n.backupCorrupt,
    ]);
    expect(backupErrorText(l10n, StateError('x')), isNull);
  });
}
