import 'dart:convert';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  const ApiException(this.status, {this.code});

  final int status;
  final String? code;

  String get message => switch (status) {
    0 => 'Connection failed.',
    408 => 'Request timed out.',
    502 => 'Invalid server response.',
    _ => 'Request failed.',
  };

  @override
  String toString() => 'ApiException ($status): $message';
}

String decodeApiUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const ApiException(502);
  }
}

Json decodeApiJson(String text) {
  try {
    final value = jsonDecode(text);
    if (value is Json) return value;
  } on FormatException {
    // JSON 解码异常可能包含正文，传输层只返回通用错误。
  }
  throw const ApiException(502);
}
