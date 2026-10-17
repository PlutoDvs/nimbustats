import 'dart:convert';
import 'dart:io';

/// `backup_state.json`: when the last export was handed to Save or Share
/// (spec §5.1, ruling R9).
///
/// It lives outside the database, so restoring an old backup cannot rewind
/// it. It is synchronous: one tiny file, read when the section opens.
class BackupStateStore {
  BackupStateStore(this._path);

  final String _path;

  static const _version = 1;

  /// Null when nothing was ever exported. A file that does not read is a
  /// [FormatException], never "never".
  DateTime? lastExport() {
    final file = File(_path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?> ||
        json['v'] != _version ||
        json['lastExportUtcMs'] is! int) {
      throw FormatException('unreadable backup state', _path);
    }
    return DateTime.fromMillisecondsSinceEpoch(
        json['lastExportUtcMs']! as int,
        isUtc: true);
  }

  /// Written to a temp file and renamed over the old one, so a crash leaves
  /// the old file whole.
  void recordExport(DateTime at) {
    File('$_path.tmp')
      ..writeAsStringSync(
          jsonEncode({'v': _version, 'lastExportUtcMs': at.millisecondsSinceEpoch}),
          flush: true)
      ..renameSync(_path);
  }
}
