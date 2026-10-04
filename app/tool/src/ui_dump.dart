/// Finding a control on screen from `adb shell uiautomator dump` output.
///
/// Flutter publishes its semantics tree to Android's accessibility layer, so
/// a control's screen-reader name -- an `IconButton`'s tooltip, say -- is in
/// the dump as the node's `content-desc`, and visible text as its `text`.
/// Pure, so the lookup is tested away from the device.
library;

typedef ScreenPoint = ({int x, int y});

/// The centre of every node whose `content-desc` or `text` has [label] as one
/// of its lines.
///
/// Whole lines, because Flutter merges a control's semantics into one node
/// joined by newlines. Every match is returned: deciding what two matches
/// mean is the caller's job, and picking one is how a tap lands on the wrong
/// button.
List<ScreenPoint> centresOf(String xml, String label) => [
      for (final node in _node.allMatches(xml))
        if (_names(node[1]!).contains(label)) _centre(node[1]!),
    ];

final _node = RegExp(r'<node\b([^>]*)>');
final _bounds = RegExp(r'^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$');

Iterable<String> _names(String attributes) => [
      for (final name in ['content-desc', 'text'])
        ...?_attribute(attributes, name)?.split('\n'),
    ];

ScreenPoint _centre(String attributes) {
  final bounds = _attribute(attributes, 'bounds');
  final match = bounds == null ? null : _bounds.firstMatch(bounds);
  if (match == null) {
    throw FormatException('a matching node has no readable bounds', attributes);
  }
  int at(int group) => int.parse(match[group]!);
  return (x: (at(1) + at(3)) ~/ 2, y: (at(2) + at(4)) ~/ 2);
}

String? _attribute(String attributes, String name) {
  final match =
      RegExp('(?:^|\\s)${RegExp.escape(name)}="([^"]*)"').firstMatch(attributes);
  return match == null ? null : _decode(match[1]!);
}

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);');

String _decode(String value) => value.replaceAllMapped(_entity, (m) {
      final entity = m[1]!;
      return switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ when entity.startsWith('#x') =>
          String.fromCharCode(int.parse(entity.substring(2), radix: 16)),
        _ => String.fromCharCode(int.parse(entity.substring(1))),
      };
    });
