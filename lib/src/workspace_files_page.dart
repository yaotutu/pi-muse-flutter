import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'file_size.dart';
import 'workspace_files.dart';

class WorkspaceFilesPage extends StatefulWidget {
  const WorkspaceFilesPage({
    super.key,
    required this.files,
    this.path = workspaceRoot,
    this.title = '工作区文件',
  });

  final WorkspaceFiles files;
  final String path;
  final String title;

  @override
  State<WorkspaceFilesPage> createState() => _WorkspaceFilesPageState();
}

class _WorkspaceFilesPageState extends State<WorkspaceFilesPage> {
  late Future<List<WorkspaceEntry>> _listing = widget.files.list(widget.path);

  void _reload() {
    final listing = widget.files.list(widget.path);
    setState(() {
      _listing = listing;
    });
  }

  void _open(WorkspaceEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => entry.directory
            ? WorkspaceFilesPage(
                files: widget.files,
                path: entry.path,
                title: entry.name,
              )
            : _WorkspaceFilePage(files: widget.files, entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: '刷新目录',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder(
          future: _listing,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snapshot.hasError) {
              return _ReadFailure(
                snapshot.error!,
                directory: true,
                onRetry: _reload,
              );
            }
            final entries = snapshot.requireData;
            if (entries.isEmpty) {
              return const Center(child: Text('这个文件夹里还没有文件'));
            }
            final colors = Theme.of(context).colorScheme;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 48),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Icon(
                        entry.directory
                            ? Icons.folder_outlined
                            : Icons.insert_drive_file_outlined,
                        color: entry.directory
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: entry.directory
                          ? null
                          : Text(formatFileSize(entry.size)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(entry),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceFilePage extends StatefulWidget {
  const _WorkspaceFilePage({required this.files, required this.entry});

  final WorkspaceFiles files;
  final WorkspaceEntry entry;

  @override
  State<_WorkspaceFilePage> createState() => _WorkspaceFilePageState();
}

class _WorkspaceFilePageState extends State<_WorkspaceFilePage> {
  late Future<WorkspaceFile> _reading = widget.files.open(widget.entry.path);

  void _reload() {
    final reading = widget.files.open(widget.entry.path);
    setState(() {
      _reading = reading;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder(
          future: _reading,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _Loading();
            }
            if (snapshot.hasError) {
              return _ReadFailure(
                snapshot.error!,
                directory: false,
                onRetry: _reload,
              );
            }
            final file = snapshot.requireData;
            final theme = Theme.of(context);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                      child: Text(
                        '${file.path}\n${formatFileSize(file.size)} · ${file.mimeType}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: switch (file.kind) {
                        WorkspaceFileKind.text => _RawFileText(file.text!),
                        WorkspaceFileKind.image => InteractiveViewer(
                          maxScale: 4,
                          child: Image(
                            image: ResizeImage(
                              MemoryImage(file.image!),
                              width: 2048,
                              height: 2048,
                              policy: ResizeImagePolicy.fit,
                            ),
                            fit: BoxFit.contain,
                            semanticLabel: widget.entry.name,
                            errorBuilder: (context, error, stack) =>
                                const Center(child: Text('无法预览这张图片')),
                          ),
                        ),
                        WorkspaceFileKind.binary => const Center(
                          child: Text('此文件格式无法预览'),
                        ),
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RawFileText extends StatelessWidget {
  const _RawFileText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const Center(child: Text('空文本文件'));
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.55);
    final ranges = _textRanges(text).toList(growable: false);
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: ranges.length,
      itemBuilder: (context, index) {
        final (start, end) = ranges[index];
        return SelectableText(text.substring(start, end), style: style);
      },
    );
  }
}

// 按块布局长文件，优先沿原文的换行分块，避免一次排版整个文件。
Iterable<(int, int)> _textRanges(String text) sync* {
  const blockSize = 4096;
  var start = 0;
  while (start + blockSize < text.length) {
    var end = start + blockSize;
    var split = end - 1;
    while (split > start + blockSize ~/ 2 && text.codeUnitAt(split) != 10) {
      split--;
    }
    if (text.codeUnitAt(split) == 10) {
      yield (start, split);
      start = split + 1;
    } else {
      final nextUnit = text.codeUnitAt(end);
      if (nextUnit >= 0xdc00 && nextUnit <= 0xdfff) end--;
      yield (start, end);
      start = end;
    }
  }
  yield (start, text.length);
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _ReadFailure extends StatelessWidget {
  const _ReadFailure(
    this.error, {
    required this.directory,
    required this.onRetry,
  });

  final Object error;
  final bool directory;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      ApiException(status: 401) => '登录已过期，请返回聊天页重新连接',
      ApiException(status: 404) => directory ? '这个文件夹已不存在' : '这个文件已不存在',
      ApiException(status: 413) =>
        directory ? '此文件夹的条目超过 1,000 项' : '文件超过 8 MiB，无法打开',
      _ => directory ? '无法读取目录' : '无法打开文件',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
