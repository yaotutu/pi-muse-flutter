# Pi Muse Flutter

## 简体中文

这是独立的 Flutter Android 客户端预览，不需要检出或运行 React Native 工程。应用使用独立包名 `com.pimuse.pi_muse_flutter`，通过 HTTP/SSE 连接 Pi Muse 服务端。打开后填写服务端根地址及访问密钥，点击「连接」。访问密钥用于换取 Session Token。连接成功后，可从主聊天进入会话列表、创建或切换会话。

聊天页采用深靛蓝主题。点左上角打开侧边栏，点居中的会话标题切换或新建会话。底栏显示「聊天」「待办」「新闻」「设置」；待办和新闻暂未启用，服务器连接从「设置」进入。用户消息显示在右侧浅蓝气泡，助手回复是宽幅卡片，保留 Markdown 层级与原文换行。已保存的回复可复制。回复实时显示，输入框右端的停止按钮结束本机发起的本轮回复。有文件修改待确认时，顶栏下方才会出现提示，点击「查看修改」可核对修改前后全文，再选择批准或拒绝。如果发送结果不明，点「核对发送结果」后再决定是否发送。

### 发送附件

点输入框左侧的「添加附件」，在 Android 系统选择器中选取图片或文本。附件会先列在输入框上方，可以移除，再与文字一起发送，也可以单独发送。每条消息最多 4 项、合计 8 MiB，其中文本合计最多 100,000 字节。支持 PNG、JPEG、GIF、WebP 和有效的 UTF-8 文本。

发送后，附件随用户消息显示。点图片可打开预览，文本附件显示名称和大小。图片理解取决于当前服务端配置的模型。发送结果不明时，先点「核对发送结果」。确认消息未保存时，原附件和文字会恢复到当前会话的草稿。

### 浏览工作区文件

打开聊天左上角的会话菜单，点「工作区文件」。列表显示连接服务器上的共享工作区，所有会话打开的是同一目录。点文件夹进入下一级，点「刷新目录」更新列表，返回键可逐级返回。

文本以可选择的原文显示，Markdown、HTML 和 SVG 都按文本打开。PNG、JPEG、GIF、WebP 可缩放预览，其他二进制文件显示名称和大小。服务端单文件读取上限为 8 MiB。本入口提供浏览和预览。

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

This standalone Flutter Android preview does not require a React Native checkout or runtime. Its application ID is `com.pimuse.pi_muse_flutter`, and it connects to the Pi Muse backend over HTTP/SSE. Enter the server origin and access key, then tap **Connect**. The app exchanges the key for a session token. Once connected, use the main chat to create or switch sessions.

The chat uses a deep indigo theme. Open the drawer with the top-left menu button, or tap the centered session title to switch or create a session. The bottom bar shows **聊天**, **待办**, **新闻**, and **设置**. To-do and News are not enabled yet; open Settings to reach the server connection. Your messages appear in light blue bubbles on the right. Assistant replies appear in wide cards with Markdown formatting and the original line breaks. You can copy saved replies. Replies stream into the conversation. The stop button at the end of the composer ends the current reply started on this device. When a file change needs approval, a banner appears below the app bar. Tap **查看修改** to read the full before and after text before approving or denying the change. If delivery is uncertain, tap **核对发送结果** to verify it before deciding whether to send again.

### Send attachments

Tap **添加附件** on the left of the composer and choose images or text files in the Android file picker. Review or remove the files above the composer, then send them with or without a message. Each message can include up to four files and 8 MiB in total, with a shared limit of 100,000 bytes for text. Supported formats are PNG, JPEG, GIF, WebP, and valid UTF-8 text.

Attachments appear with the user message after sending. Tap an image to preview it. Text attachments show their name and size. Image understanding depends on the model configured on the server. If delivery is uncertain, tap **核对发送结果**. Once the app confirms the message was not saved, it restores the original files and text to that conversation's draft.

### Browse workspace files

Open the menu in the top-left corner of the chat and tap **工作区文件**. Every conversation shares the same workspace on the connected server. Tap a folder to open it, use **刷新目录** to refresh the list, and use Back to return to its parent.

Text files open as selectable source, including Markdown, HTML, and SVG. PNG, JPEG, GIF, and WebP images can be zoomed. Other binary files show their name and size. The server reads files up to 8 MiB. This screen provides browsing and previews.

### Run and check locally

Use Flutter 3.50.1, JDK 17 or a compatible version, Android SDK 36, and an Android emulator. Run the commands in the section above from this directory. An Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after forwarding the port with `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen with default graphics, retry with `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>`. Acceptance uses the backend from current source, a real model, and `/docs` rendered in a browser.
