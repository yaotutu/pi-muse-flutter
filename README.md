# Pi Muse Flutter

## 简体中文

这是独立的 Flutter Android 客户端预览，不需要检出或运行 React Native 工程。应用使用独立包名 `com.pimuse.pi_muse_flutter`，通过 HTTP/SSE 连接 Pi Muse 服务端。打开后填写服务端根地址及访问密钥，点击「连接」。访问密钥用于换取 Session Token。连接成功后，可从主聊天进入会话列表、创建或切换会话。

聊天页使用 Material 顶栏：左侧切换会话，标题显示当前会话，右侧齿轮打开「服务器连接」。用户消息显示在右侧气泡；助手回复带有 Pi Muse 标记，以适合聊天阅读的字号呈现 Markdown，并保留原文换行。回复实时显示，输入框右端的停止按钮结束本机发起的本轮回复。有文件修改待确认时，顶栏下方才会出现提示，点击「查看修改」可核对修改前后全文，再选择批准或拒绝。如果发送结果不明，点「核对发送结果」后再决定是否发送。

### 本地运行和检查

需要 Flutter 3.50.1、JDK 17 或兼容版本、Android SDK 36 和 Android 模拟器。在本目录执行：

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d <android-device-id>
```

在 Android 模拟器连接宿主机服务时，可用 `http://10.0.2.2:12330`。如果已经用 `adb reverse tcp:12330 tcp:12330` 映射端口，也可使用 `http://127.0.0.1:12330`。如果模拟器默认图形模式卡在启动画面，可用 `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>` 复验。验收使用当前源码运行的 Pi Muse 后端、真实模型和浏览器实际渲染的 `/docs`。

## English

This standalone Flutter Android preview does not require a React Native checkout or runtime. Its application ID is `com.pimuse.pi_muse_flutter`, and it connects to the Pi Muse backend over HTTP/SSE. Enter the server origin and access key, then tap **Connect**. The app exchanges the key for a session token. Once connected, open the conversation picker from the main chat to create or switch sessions.

The Material top app bar shows the conversation picker on the left, the current conversation title, and a settings button for **服务器连接** on the right. Your messages appear in right-aligned bubbles. Assistant replies have a Pi Muse label and use compact Markdown typography that preserves the original line breaks. Replies stream into the conversation. The stop button at the end of the composer ends the current reply started on this device. When a file change needs approval, a banner appears below the app bar. Tap **查看修改** to read the full before and after text before approving or denying the change. If delivery is uncertain, tap **核对发送结果** to verify it before deciding whether to send again.

### Run and check locally

Use Flutter 3.50.1, JDK 17 or a compatible version, Android SDK 36, and an Android emulator. Run the commands in the section above from this directory. An Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after forwarding the port with `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen with default graphics, retry with `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>`. Acceptance uses the backend from current source, a real model, and `/docs` rendered in a browser.
