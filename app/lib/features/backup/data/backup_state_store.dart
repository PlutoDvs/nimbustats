import 'dart:convert';
import 'dart:io';

/// `backup_state.json`: when the last export was handed to Save or Share
/// (spec §5.1, ruling R9), and which way the undo copy points.
///
/// `{"v":1, "lastExportUtcMs"?: int, "undoRedoes"?: bool}`.
///
/// It lives outside the database, so restoring an old backup cannot rewind
/// it. It is synchronous: one tiny file, read when the section opens.
class BackupStateStore {
  BackupStateStore(this._path);

  final String _path;

  static const _version = 1;
  static const _lastExport = 'lastExportUtcMs';
  static const _undoRedoes = 'undoRedoes';

  /// Null when nothing was ever exported. A file that does not read is a
  /// [FormatException], never "never".
  DateTime? lastExport() => switch (_read()[_lastExport]) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        _ => null,
      };

  void recordExport(DateTime at) => _write(_lastExport, at.millisecondsSinceEpoch);

  /// True when the undo copy holds what an undo replaced, so tapping it
  /// re-applies the restore. False after a restore, or when never set.
  bool undoRedoes() => _read()[_undoRedoes] == true;

  void setUndoRedoes(bool value) => _write(_undoRedoes, value);

  /// The fields as stored; only the version when there is no file.
  Map<String, Object?> _read() {
    final file = File(_path);
    if (!file.existsSync()) return {'v': _version};
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?> ||
        json['v'] != _version ||
        json.entries.any((field) => !switch (field) {
              MapEntry(key: 'v') ||
              MapEntry(key: _lastExport, value: int()) ||
              MapEntry(key: _undoRedoes, value: bool()) =>
                true,
              _ => false,
            })) {
      throw FormatException('unreadable backup state', _path);
    }
    return json;
  }

  /// Keeps the other field. Written to a temp file and renamed over the old
  /// one, so a crash leaves the old file whole.
  void _write(String key, Object value) {
    File('$_path.tmp')
      ..writeAsStringSync(jsonEncode({..._read(), key: value}), flush: true)
      ..renameSync(_path);
  }
}
