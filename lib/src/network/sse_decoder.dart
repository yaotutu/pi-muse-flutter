import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'api_response.dart';

class SseFrame {
  const SseFrame({this.event, required this.data});

  final String? event;
  final Json data;
}

const _maxSseFrameBytes = 12 * 1024 * 1024;

Stream<SseFrame> decodeSse(Stream<List<int>> bytes) async* {
  yield* bytes
      .expand(_SseDecoder().add)
      .transform(
        StreamTransformer<SseFrame, SseFrame>.fromHandlers(
          handleError: (error, stack, sink) {
            sink.addError(error, stack);
            sink.close();
          },
        ),
      );
}

class _SseDecoder {
  final _frame = BytesBuilder();
  bool _lineHasContent = false;
  bool _skipLf = false;
  bool _atStart = true;

  Iterable<SseFrame> add(List<int> chunk) sync* {
    var start = 0;
    for (var index = 0; index < chunk.length; index++) {
      final byte = chunk[index];
      if (_skipLf) {
        _skipLf = false;
        if (byte == 10) continue;
      }
      if (byte != 10 && byte != 13) {
        _lineHasContent = true;
        continue;
      }
      _skipLf = byte == 13;
      if (_lineHasContent) {
        _lineHasContent = false;
        continue;
      }

      // CR/LF 不会出现在 UTF-8 多字节字符内部。仅在完整帧到达后解码，EOF 丢弃残帧。
      _append(chunk, start, index);
      start = index + 1;
      final frame = _decodeFrame(_frame.takeBytes());
      if (frame != null) yield frame;
    }
    _append(chunk, start, chunk.length);
  }

  void _append(List<int> chunk, int start, int end) {
    if (_frame.length + end - start > _maxSseFrameBytes) {
      throw const ApiException(502);
    }
    if (end == start) return;
    _frame.add(
      start == 0 && end == chunk.length ? chunk : chunk.sublist(start, end),
    );
  }

  SseFrame? _decodeFrame(Uint8List bytes) {
    var text = decodeApiUtf8(bytes);
    // Dart 解码时会去掉起始 BOM，SSE 只允许在整个流开头去掉一次。
    if (!_atStart &&
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      text = '﻿$text';
    }
    _atStart = false;

    String? event;
    final data = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty || line.startsWith(':')) continue;
      final separator = line.indexOf(':');
      final field = separator < 0 ? line : line.substring(0, separator);
      var value = separator < 0 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      if (field == 'event') event = value.isEmpty ? null : value;
      if (field == 'data') data.add(value);
    }
    if (data.isEmpty) return null;
    return SseFrame(event: event, data: decodeApiJson(data.join('\n')));
  }
}
