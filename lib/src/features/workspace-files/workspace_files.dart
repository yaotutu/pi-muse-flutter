import 'dart:convert';
import 'dart:typed_data';

import '../../network/api.dart';

const workspaceRoot = '.';

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.directory,
    required this.size,
  });

  final String name;
  final String path;
  final bool directory;
  final int size;
}

enum WorkspaceFileKind { text, image, binary }

class WorkspaceFile {
  const WorkspaceFile({
    required this.path,
    required this.size,
    required this.mimeType,
    required this.kind,
    this.text,
    this.image,
  });

  final String path;
  final int size;
  final String mimeType;
  final WorkspaceFileKind kind;
  final String? text;
  final Uint8List? image;
}

class WorkspaceFiles {
  const WorkspaceFiles(this._api);

  final MuseApi _api;

  Future<List<WorkspaceEntry>> list(String directory) async {
    final result = await _api.get(
      '/api/workspace/files',
      query: {'path': directory},
    );
    if (result['path'] != directory) throw const FormatException();
    return (result['entries'] as List)
        .cast<Json>()
        .map((entry) {
          final name = entry['name'] as String;
          final path = entry['path'] as String;
          final expectedPath = directory == workspaceRoot
              ? name
              : '$directory/$name';
          final size = entry['size'] as int;
          final kind = entry['kind'];
          if (name.isEmpty ||
              name == '.' ||
              name == '..' ||
              name.contains('/') ||
              path != expectedPath ||
              size < 0 ||
              (kind != 'directory' && kind != 'file')) {
            throw const FormatException();
          }
          return WorkspaceEntry(
            name: name,
            path: path,
            directory: kind == 'directory',
            size: size,
          );
        })
        .toList(growable: false);
  }

  Future<WorkspaceFile> open(String path) async {
    final result = await _api.get(
      workspaceFileContentPath,
      query: {'path': path},
    );
    final size = result['size'] as int;
    if (result['path'] != path || size < 0 || size > maxWorkspaceFileBytes) {
      throw const FormatException();
    }
    final kind = switch (result['kind']) {
      'text' => WorkspaceFileKind.text,
      'image' => WorkspaceFileKind.image,
      'binary' => WorkspaceFileKind.binary,
      _ => throw const FormatException(),
    };
    return WorkspaceFile(
      path: path,
      size: size,
      mimeType: result['mimeType'] as String,
      kind: kind,
      text: kind == WorkspaceFileKind.text ? result['content'] as String : null,
      image: kind == WorkspaceFileKind.image
          ? _decodeImage(result['dataBase64'] as String, size)
          : null,
    );
  }
}

Uint8List _decodeImage(String encoded, int size) {
  if (encoded.length != ((size + 2) ~/ 3) * 4) throw const FormatException();
  final image = base64Decode(encoded);
  if (image.length != size) throw const FormatException();
  return image.asUnmodifiableView();
}
