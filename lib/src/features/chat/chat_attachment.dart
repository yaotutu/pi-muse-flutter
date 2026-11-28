import 'dart:convert';

import 'package:flutter/services.dart';

import '../../network/api.dart';

const maxChatAttachments = 4;
const maxChatAttachmentBytes = 8 * 1024 * 1024;
const maxChatAttachmentTextBytes = 100000;

const _imageTypes = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'};
const _textTypes = {
  'text/plain',
  'text/markdown',
  'text/csv',
  'text/html',
  'image/svg+xml',
  'application/json',
  'application/xml',
  'text/xml',
  'application/yaml',
  'text/yaml',
  'application/javascript',
  'text/javascript',
  'text/typescript',
  'application/sql',
  'text/css',
};
const _textExtensions = {
  'txt',
  'md',
  'markdown',
  'csv',
  'json',
  'xml',
  'yaml',
  'yml',
  'js',
  'mjs',
  'cjs',
  'jsx',
  'ts',
  'tsx',
  'py',
  'rb',
  'go',
  'rs',
  'java',
  'kt',
  'kts',
  'c',
  'h',
  'cpp',
  'hpp',
  'cs',
  'php',
  'sql',
  'sh',
  'bash',
  'zsh',
  'css',
  'scss',
  'less',
  'html',
  'htm',
  'svg',
};
final _invalidFileName = RegExp(r'[\\/\x00-\x1f\x7f]');

class ChatAttachment {
  const ChatAttachment(
    this.id,
    this.name,
    this.mimeType,
    this.size, {
    this.isImage = false,
    this.imageBytes,
  });

  factory ChatAttachment.fromJson(Json json) {
    final mimeType = json['mimeType'] as String;
    final size = json['size'] as int;
    final isImage = json['kind'] == 'image';
    final image = json['image'];
    Uint8List? bytes;
    if (isImage && image is Json && _imageTypes.contains(image['mimeType'])) {
      final encoded = image['dataBase64'];
      if (encoded is String &&
          encoded.length <= ((maxChatAttachmentBytes + 2) ~/ 3) * 4) {
        try {
          final decoded = base64Decode(encoded);
          if (decoded.length <= maxChatAttachmentBytes &&
              _imageType(decoded) == image['mimeType']) {
            bytes = decoded.asUnmodifiableView();
          }
        } on FormatException {
          // 保留历史附件名称，坏掉的预览不影响读取对话。
        }
      }
    }
    return ChatAttachment(
      json['id'] as String,
      json['name'] as String,
      mimeType,
      size,
      isImage: isImage,
      imageBytes: bytes,
    );
  }

  final String id;
  final String name;
  final String mimeType;
  final int size;
  final bool isImage;
  final Uint8List? imageBytes;
}

class PickedAttachment {
  const PickedAttachment(this.name, this.mimeType, this.bytes);

  final String name;
  final String? mimeType;
  final Uint8List bytes;
}

class DraftAttachment extends ChatAttachment {
  DraftAttachment._(String id, String name, String mime, this._bytes)
    : super(
        id,
        name,
        mime,
        _bytes.length,
        isImage: _imageTypes.contains(mime),
        imageBytes: _imageTypes.contains(mime) ? _bytes : null,
      );

  final Uint8List _bytes;

  Json toRequest() => {
    'id': id,
    'name': name,
    'mimeType': mimeType,
    'dataBase64': base64Encode(_bytes),
  };
}

class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;
}

List<DraftAttachment> appendChatAttachments(
  List<DraftAttachment> existing,
  List<PickedAttachment> picked,
  String Function() newId,
) {
  if (existing.length + picked.length > maxChatAttachments) {
    throw const AttachmentException('每条消息最多可添加 4 个附件');
  }
  var totalBytes = 0;
  var textBytes = 0;
  for (final attachment in existing) {
    totalBytes += attachment.size;
    if (!attachment.isImage) textBytes += attachment.size;
  }
  final added = <DraftAttachment>[];
  for (final file in picked) {
    final bytes = file.bytes;
    if (file.name.isEmpty ||
        file.name.length > 200 ||
        _invalidFileName.hasMatch(file.name)) {
      throw const AttachmentException('文件名不受支持');
    }
    if (bytes.isEmpty) throw const AttachmentException('无法添加空文件');
    totalBytes += bytes.length;
    if (totalBytes > maxChatAttachmentBytes) {
      throw const AttachmentException('附件总大小不能超过 8 MiB');
    }
    final mime = _attachmentType(file);
    if (!_imageTypes.contains(mime)) {
      textBytes += bytes.length;
      if (textBytes > maxChatAttachmentTextBytes) {
        throw const AttachmentException('文本附件合计不能超过 100,000 字节');
      }
      try {
        if (bytes.contains(0)) throw const FormatException();
        utf8.decode(bytes);
      } on FormatException {
        throw const AttachmentException('文本附件必须是有效的 UTF-8 文件');
      }
    }
    added.add(
      DraftAttachment._(newId(), file.name, mime, bytes.asUnmodifiableView()),
    );
  }
  return List.unmodifiable([...existing, ...added]);
}

String _attachmentType(PickedAttachment file) {
  const generic = 'application/octet-stream';
  final reported = file.mimeType?.split(';').first.trim().toLowerCase();
  final detected = _imageType(file.bytes);
  if (detected != null &&
      (reported == null ||
          reported.isEmpty ||
          reported == generic ||
          detected == reported)) {
    return detected;
  }
  if (detected != null || _imageTypes.contains(reported)) {
    throw const AttachmentException('图片格式与文件内容不一致');
  }
  if (_textTypes.contains(reported)) return reported!;
  final dot = file.name.lastIndexOf('.');
  if (dot >= 0 &&
      _textExtensions.contains(file.name.substring(dot + 1).toLowerCase())) {
    return generic;
  }
  throw const AttachmentException('请选择 PNG、JPEG、GIF、WebP 图片或 UTF-8 文本');
}

String? _imageType(Uint8List bytes) {
  bool matches(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (matches(const [137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
  if (matches(const [255, 216, 255])) return 'image/jpeg';
  if (matches(const [71, 73, 70, 56, 55, 97]) ||
      matches(const [71, 73, 70, 56, 57, 97])) {
    return 'image/gif';
  }
  if (matches(const [82, 73, 70, 70]) && matches(const [87, 69, 66, 80], 8)) {
    return 'image/webp';
  }
  return null;
}

typedef ChatAttachmentPicker =
    Future<List<PickedAttachment>> Function({
      required int maxFiles,
      required int maxBytes,
    });

Future<List<PickedAttachment>> pickAndroidChatAttachments({
  required int maxFiles,
  required int maxBytes,
}) async {
  const channel = MethodChannel('pi_muse/attachments');
  try {
    final files = await channel.invokeListMethod<Map>('pick', {
      'maxFiles': maxFiles,
      'maxBytes': maxBytes,
    });
    return (files ?? const [])
        .map(
          (file) => PickedAttachment(
            file['name'] as String,
            file['mimeType'] as String?,
            file['bytes'] as Uint8List,
          ),
        )
        .toList();
  } on PlatformException catch (error) {
    throw AttachmentException(switch (error.code) {
      'too_many' => '每条消息最多可添加 4 个附件',
      'too_large' => '附件总大小不能超过 8 MiB',
      'busy' => '文件选择器已打开',
      _ => '无法读取选中的文件',
    });
  }
}
