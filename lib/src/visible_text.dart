// 同一投影用于流式回复和历史，私有思考块即使尚未闭合也不显示。
final _thinkTag = RegExp(r'</think\s*>|<think\b[^>]*>', caseSensitive: false);
final _partialTag = RegExp(
  r'^</?(?:t(?:h(?:i(?:n(?:k\b[^>]*)?)?)?)?)?$',
  caseSensitive: false,
);
final _markdownControl = RegExp(
  r'^ {0,3}(`{3,}|~{3,})[^\n]*|`+|<',
  multiLine: true,
);
final _backticks = RegExp(r'`+');

String visibleAssistantText(String text) {
  final visible = StringBuffer();
  var position = 0;
  for (final match in _markdownControl.allMatches(text)) {
    if (match.start < position) continue;
    visible.write(text.substring(position, match.start));
    position = match.end;
    final fence = match[1];
    if (fence != null) {
      final closing = RegExp(
        '^ {0,3}${fence[0]}{${fence.length},}'
        r'[ \t]*\r?$',
        multiLine: true,
      );
      final end =
          closing.allMatches(text, position).firstOrNull?.end ?? text.length;
      visible.write(text.substring(match.start, end));
      position = end;
    } else if (match[0]!.startsWith('`')) {
      final paragraphEnd = text.indexOf('\n\n', position);
      final close = _backticks
          .allMatches(text, position)
          .firstWhereOrNull(
            (ticks) =>
                ticks[0] == match[0] &&
                (paragraphEnd < 0 || ticks.start < paragraphEnd),
          );
      if (close != null) position = close.end;
      visible.write(text.substring(match.start, position));
    } else {
      final tag = _thinkTag.matchAsPrefix(text, match.start);
      if (tag != null) {
        position = tag.end;
        if (tag[0]!.startsWith('</')) continue;
        var depth = 1;
        for (final following in _thinkTag.allMatches(text, position)) {
          depth += following[0]!.startsWith('</') ? -1 : 1;
          if (depth == 0) {
            position = following.end;
            break;
          }
        }
        if (depth != 0) return visible.toString();
        if (visible.isEmpty) {
          while (position < text.length && '\r\n'.contains(text[position])) {
            position++;
          }
        }
      } else if (_partialTag.hasMatch(text.substring(match.start))) {
        return visible.toString();
      } else {
        visible.write('<');
      }
    }
  }
  return (visible..write(text.substring(position))).toString();
}

extension on Iterable<RegExpMatch> {
  RegExpMatch? firstWhereOrNull(bool Function(RegExpMatch) predicate) {
    for (final match in this) {
      if (predicate(match)) return match;
    }
    return null;
  }
}
