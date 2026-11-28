import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_update.dart';
import 'app_update_releases.dart';

class AppUpdateSheet extends StatelessWidget {
  const AppUpdateSheet({super.key, required this.controller});

  final AppUpdateController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('应用更新')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final version = controller.currentVersion;
            final release = controller.release;
            final status = controller.status;
            final downloading = status == AppUpdateStatus.downloading;
            final progress = downloading
                ? controller.bytesWritten / release!.size
                : null;
            final heading = switch (status) {
              AppUpdateStatus.loading => '正在读取版本',
              AppUpdateStatus.unsupported => '应用内更新不可用',
              AppUpdateStatus.idle => '尚未检查更新',
              AppUpdateStatus.checking => '正在检查更新',
              AppUpdateStatus.unpublished => '目前没有可获取的正式发布',
              AppUpdateStatus.current => '已是最新版本',
              AppUpdateStatus.downloading =>
                '正在下载更新 · ${(progress! * 100).floor()}%',
              AppUpdateStatus.ready => '安装包已下载',
              AppUpdateStatus.permission => '需要安装授权',
              AppUpdateStatus.installing => '正在打开系统安装界面',
              AppUpdateStatus.cancelled => '更新已取消',
              AppUpdateStatus.checkFailed => '检查更新失败',
              AppUpdateStatus.downloadFailed => '安装包未就绪',
              AppUpdateStatus.installFailed => '无法启动安装',
            };
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (version != null) Text('当前版本 $version'),
                    if (release != null) Text('更新版本 ${release.version}'),
                    const SizedBox(height: 16),
                    Text(
                      heading,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (controller.message case final message?) Text(message),
                    if (downloading || status == AppUpdateStatus.checking) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: progress),
                    ],
                    const SizedBox(height: 16),
                    ..._actions(status),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _actions(AppUpdateStatus status) {
    final busy = controller.busy;
    final check = FilledButton(
      onPressed: busy ? null : () => controller.check(manual: true),
      child: const Text('检查更新'),
    );
    final retry = OutlinedButton(
      onPressed: busy ? null : controller.retryDownload,
      child: const Text('重新下载安装包'),
    );
    final install = FilledButton(
      onPressed: busy ? null : controller.install,
      child: const Text('继续安装'),
    );
    return switch (status) {
      AppUpdateStatus.loading ||
      AppUpdateStatus.unsupported ||
      AppUpdateStatus.installing => [],
      AppUpdateStatus.checking || AppUpdateStatus.downloading => [
        OutlinedButton(onPressed: controller.cancel, child: const Text('取消')),
      ],
      AppUpdateStatus.ready => [install],
      AppUpdateStatus.permission => [
        FilledButton(
          onPressed: busy ? null : controller.openInstallSettings,
          child: const Text('打开授权设置'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : controller.install,
          child: const Text('继续安装'),
        ),
      ],
      AppUpdateStatus.installFailed => [
        install,
        const SizedBox(height: 8),
        retry,
      ],
      AppUpdateStatus.cancelled || AppUpdateStatus.downloadFailed => [
        check,
        if (controller.release != null) ...[const SizedBox(height: 8), retry],
      ],
      AppUpdateStatus.checkFailed => [
        check,
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Clipboard.setData(
            const ClipboardData(text: latestApkDownloadUrl),
          ),
          child: const Text('复制官方下载地址'),
        ),
      ],
      AppUpdateStatus.idle ||
      AppUpdateStatus.current ||
      AppUpdateStatus.unpublished => [check],
    };
  }
}
