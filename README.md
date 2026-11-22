# Pi Muse Flutter

## 简体中文

这是独立的 Flutter Android 客户端预览，不需要检出或运行 React Native 工程。应用使用独立包名 `com.pimuse.pi_muse_flutter`，通过 HTTP/SSE 连接 Pi Muse 服务端。打开后填写服务端根地址及访问密钥，点击「连接」。访问密钥用于换取 Session Token。连接成功后，可从主聊天进入会话列表、创建或切换会话。

顶部居中的企鹅显示当前会话状态，键盘弹起时会缩小。回复实时出现在对话里，输入框旁的停止按钮结束本机发起的本轮回复。等待文件审批时，点击状态旁的「查看修改」，核对修改前后全文，再选择批准或拒绝。如果发送结果不明，点「核对发送结果」后再决定是否发送。服务器连接入口在右上角。

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

The centered penguin at the top shows the active conversation’s status and gets smaller while the keyboard is open. Replies stream into the conversation. The stop button beside the composer ends the current reply started on this device. When a file change needs approval, tap **查看修改** beside the status to read the full before and after text before approving or denying it. If delivery is uncertain, tap **核对发送结果** to verify it before deciding whether to send again. Server connection settings are at the upper right.

### Run and check locally

Use Flutter 3.50.1, JDK 17 or a compatible version, Android SDK 36, and an Android emulator. Run the commands in the section above from this directory. An Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after forwarding the port with `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen with default graphics, retry with `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>`. Acceptance uses the backend from current source, a real model, and `/docs` rendered in a browser.
