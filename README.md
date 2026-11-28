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
- [日程、待办与提醒](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/agenda.md)
- [附件、工作区文件与审批](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/files-and-approvals.md)
- [外观、连接、MCP 与应用更新](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/profile-and-settings.md)

### 日程

底栏「日程」把月历和事项列表放在一页，事项保存在服务端：

- 月历标出当天的安排、截止和待触发提醒，点选某一天把列表筛选到这一天，再点一次取消筛选。
- 列表可切换「未完成」和「全部」，并按标题或备注搜索；右上角「新建事项」新建一条事项。
- 事项详情页可改标题、备注、安排时间和截止时间，添加、修改或取消提醒，也能标记完成、重新打开和置顶。标记完成会取消该事项尚未触发的提醒，重新打开不会恢复它们。
- 聊天里让助手记录的事项以卡片出现在聊天中，点「查看事项」或「修改时间」直接打开同一条事项。

操作步骤见 [Pi Muse 用户手册：日程、待办与提醒](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/agenda.md)，客户端实现约定见 [docs/agenda-client.md](docs/agenda-client.md)。

### 本地开发

使用 [CI 声明的 Flutter 版本](.github/workflows/ci.yml)、JDK 17 和 Android SDK；运行应用时需要 Android 设备或模拟器。在本目录执行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <android-device-id>
```

本地设备验收优先使用 `TB300FU` 实体平板：用 `adb devices -l` 确认识别为 `device`，并将其设备序列号传给 `flutter run -d`。平板与开发机在同一网络时可填写开发机的局域网地址；通过 USB 连接时，也可执行 `adb -s <android-device-id> reverse tcp:12330 tcp:12330` 后在应用中填写 `http://127.0.0.1:12330`。仅在平板无法连接时回退到模拟器。

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
- [Agenda, to-dos, and reminders](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/agenda.md)
- [Attachments, workspace files, and approvals](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/files-and-approvals.md)
- [Appearance, connection, MCP, and app updates](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/profile-and-settings.md)

### Agenda

The 日程 (Agenda) bottom-bar entry puts a month calendar and the item list on one page; items live on the server:

- The calendar marks each day's schedule, deadline, and pending reminders. Tapping a day filters the list to that day; tapping it again clears the filter.
- The list switches between 未完成 (Unfinished) and 全部 (All) and searches titles and notes; the 「新建事项」 (New item) button in the top right creates an item.
- The item page edits the title, notes, schedule, and deadline, adds, moves, or cancels reminders, and marks the item complete, reopens it, or pins it. Completing an item cancels its pending reminders; reopening does not restore them.
- Items the assistant records in chat appear as cards; tapping 查看事项 (View item) or 修改时间 (Edit time) opens the same item.

See the [Pi Muse manual: Agenda, to-dos, and reminders](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/en/agenda.md) for the steps and [docs/agenda-client.md](docs/agenda-client.md) for the client implementation rules.

### Local development

Use the [Flutter version pinned in CI](.github/workflows/ci.yml), JDK 17, and the Android SDK. Running the app requires an Android device or emulator. Run the commands in the Chinese section above from this repository root.

For local device acceptance, use the physical `TB300FU` tablet first. Check that `adb devices -l` lists it as `device` and pass its serial to `flutter run -d`. On the same network, use the development machine’s LAN address. Over USB, run `adb -s <android-device-id> reverse tcp:12330 tcp:12330` and enter `http://127.0.0.1:12330` in the app. Use an emulator only if the tablet cannot connect.

The Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen, retry `flutter run` with `--no-enable-impeller --enable-software-rendering`. The Debug APK is at `build/app/outputs/flutter-apk/app-debug.apk`.

See [AGENTS.md](AGENTS.md) for module ownership, checks, and acceptance, and the [Android release guide](docs/android-release.md) for signing and releases.
