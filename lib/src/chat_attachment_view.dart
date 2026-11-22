import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'chat_attachment.dart';

class ChatAttachmentTile extends StatelessWidget {
  const ChatAttachmentTile({
    super.key,
    required this.attachment,
    this.onRemove,
  });

  final ChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bytes = attachment.imageBytes;
    final icon = Icon(
      attachment.isImage ? Icons.image_outlined : Icons.description_outlined,
      size: 21,
      color: colors.onSurfaceVariant,
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: bytes == null ? null : () => _preview(context, bytes),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox.square(
                        dimension: 36,
                        child: bytes == null
                            ? icon
                            : Image(
                                image: _imageProvider(bytes, 144),
                                fit: BoxFit.cover,
                                excludeFromSemantics: true,
                                errorBuilder: (context, error, stack) => icon,
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: attachment.name,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              _sizeLabel(attachment.size),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onRemove case final remove?)
            IconButton(
              tooltip: '移除 ${attachment.name}',
              onPressed: remove,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context, Uint8List bytes) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          attachment.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SizedBox(
          width: 520,
          height: MediaQuery.sizeOf(context).height * .48,
          child: InteractiveViewer(
            maxScale: 4,
            child: Image(
              image: _imageProvider(bytes, 2048),
              fit: BoxFit.contain,
              semanticLabel: attachment.name,
              errorBuilder: (context, error, stack) =>
                  const Center(child: Text('无法预览这张图片')),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

ImageProvider _imageProvider(Uint8List bytes, int bound) => ResizeImage(
  MemoryImage(bytes),
  width: bound,
  height: bound,
  policy: ResizeImagePolicy.fit,
);

String _sizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
