# Pi Muse Flutter

[简体中文](#简体中文) · [English](#english)

## 简体中文

Pi Muse 的 Flutter Android 客户端，通过 HTTP/SSE 连接自部署的 [Pi Muse 服务端](https://github.com/yaotutu/pi-muse)。应用 ID 为 `com.pimuse.pi_muse_flutter`。

### 安装与连接

1. 从 [Flutter Releases](https://github.com/yaotutu/pi-muse-flutter/releases) 下载 `app-release.apk` 并在 Android 上安装。覆盖安装要求包名与签名一致；若需要先卸载旧安装，卸载会清除本机应用数据。
2. 首次打开时输入手机能访问的服务端根地址与服务端访问密钥，点击「连接」。不要填写模型 API key。HTTP 不加密；优先使用可信网络或 HTTPS。
3. 在「聊天」发送一条消息。修改连接从「设置 → 服务器连接」进入。

操作说明统一在 [Pi Muse 用户手册](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/index.md) 维护：

- [对话、会话与短信同步](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/conversations-and-agents.md)
- [附件、工作区文件与审批](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/files-and-approvals.md)
- [外观、连接、MCP 与应用更新](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/profile-and-settings.md)

### 本地开发

使用 [CI 声明的 Flutter 版本](.github/workflows/ci.yml)、JDK 17 和 Android SDK；运行应用时需要 Android 设备或模拟器。在本目录执行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <android-device-id>
```

在 Android 模拟器连接宿主机服务时，可填 `http://10.0.2.2:12330`。如果已执行 `adb reverse tcp:12330 tcp:12330`，也可填 `http://127.0.0.1:12330`。模拟器卡在启动画面时，可加 `--no-enable-impeller --enable-software-rendering` 复验。Debug APK 位于 `build/app/outputs/flutter-apk/app-debug.apk`。

模块职责、门禁和真实验收见 [AGENTS.md](AGENTS.md)，签名与发版见 [Android 发布指南](docs/android-release.md)。

## English

The Pi Muse Flutter client for Android connects to a self-hosted [Pi Muse server](https://github.com/yaotutu/pi-muse) over HTTP/SSE. Its application ID is `com.pimuse.pi_muse_flutter`.

### Install and connect

1. Download `app-release.apk` from [Flutter Releases](https://github.com/yaotutu/pi-muse-flutter/releases) and install it on Android. Updating in place requires the same application ID and signing certificate. If you need to uninstall an existing build first, uninstalling clears the app's local data.
2. On first launch, enter the server base address reachable from the phone and the server access key, then tap **连接** (Connect). Do not enter the model API key. Plain HTTP is not encrypted; use a trusted network or HTTPS.
3. Send a message in **聊天** (Chat). To change the connection, open **设置 → 服务器连接** (Settings → Server connection).

The [Pi Muse user manual](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/index.md) is the source for usage instructions:

- [Chat, sessions, and SMS sync](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/conversations-and-agents.md)
- [Attachments, workspace files, and approvals](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/files-and-approvals.md)
- [Appearance, connection, MCP, and app updates](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/profile-and-settings.md)

### Local development

Use the [Flutter version pinned in CI](.github/workflows/ci.yml), JDK 17, and the Android SDK. Running the app requires an Android device or emulator. Run the commands in the Chinese section above from this repository root.

The Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen, retry `flutter run` with `--no-enable-impeller --enable-software-rendering`. The Debug APK is at `build/app/outputs/flutter-apk/app-debug.apk`.

See [AGENTS.md](AGENTS.md) for module ownership, checks, and acceptance, and the [Android release guide](docs/android-release.md) for signing and releases.
