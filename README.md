# Pi Muse Flutter

## 简体中文

这是独立的 Flutter Android 客户端预览，不需要检出或运行 React Native 工程。应用使用独立包名 `com.pimuse.pi_muse_flutter`，通过 HTTP/SSE 连接 Pi Muse 服务端。打开后填写服务端根地址及访问密钥，点击「连接」。访问密钥用于换取 Session Token。连接成功后，可从主聊天进入会话列表、创建或切换会话。

点左上角打开侧边栏，选择会话或点「新建会话」。顶部居中显示当前会话名称。底栏显示「聊天」「待办」「新闻」「设置」；待办和新闻暂未启用，服务器连接从「设置」进入。用户消息显示在右侧气泡，助手回复是宽幅卡片，保留 Markdown 层级与原文换行。回复实时显示。有文件修改待确认时，顶栏下方才会出现提示，点击「查看修改」可核对修改前后全文，再选择批准或拒绝。如果发送结果不明，点「核对发送结果」后再决定是否发送。

### 查看执行详情

点聊天右上角的「执行详情」。**动态**显示当前会话的运行阶段、工具与子任务，有待审批时可跳转到对应列表。**审批**可查看待处理的文件修改和已处理的记录，历史预览会同时显示审批结果与实际写入回执。**历史**显示当前会话已登记的活动，点开可看目标、进度、结果与执行步骤。普通聊天可能没有活动记录。返回键回到聊天，草稿和正在生成的回复会保留。

### 操作消息

已保存的消息下方提供复制和引用按钮。可反馈的消息还会显示点赞、不喜欢和书签按钮。点书签收藏，再点一次取消收藏。收藏由服务器保存，可以与点赞或不喜欢同时使用。点亮的图标表示当前状态。结果不明时，先点消息下方的「核对反馈状态」。引用会显示在输入框上方，可移除，写好追问或添加附件后随下一条消息发送。

本机正在生成回复时，输入框右侧显示「停止回复」。输入下一条或添加附件后，按钮变为「停止并发送」。客户端在确认上一轮停止并同步历史后发送下一条。如果无法确认，下一条保留在输入框。若上一条也未保存，可通过「切换未发送草稿」找回两条内容。

### 管理会话

打开左侧边栏，在专题会话的「更多操作」中可重命名或删除。重命名保留历史和草稿。删除会永久移除该会话的聊天历史和反馈，确认前会显示关联的定时任务和网页监控。有任务或监控时，可选择一并删除，或保留并转到默认会话。删除当前会话后会回到默认会话。

### 设置

底栏的「设置」和聊天侧栏的「设置」都进入同一个设置首页。首页保留底栏，可直接切回「聊天」。点「外观」「服务器连接」「短信同步」或「应用更新」进入对应页面，返回时回到设置首页。

### 更换配色

打开「设置 → 外观」，在「配色」中选择靛蓝（默认）、森林绿、暖棕或紫色。点选后立即生效，下次打开应用时恢复上次保存的配色。设置仅保存在本机，浅色和深色仍自动跟随系统。

### 同步新短信

打开「设置 → 短信同步」，开启「同步新短信」并授予 Android 接收短信权限。开启后新收到的短信原文和发件人会发送到当前连接的 Pi Muse 服务端。HTTP 连接传输时未加密。后台可继续同步，断网时短信加密保存在本机，恢复网络后继续上传。关闭同步或撤回权限会暂停接收和上传，已排队的短信会保留。

页面显示待同步数量和最近一次确认服务端已接收的时间。服务器恢复接收后，点「立即同步」。如果连接失效，先到「服务器连接」重新连接。重新登录或更新服务器地址会保留待传短信。发送结果不明时，应用先向服务端核对，确认未找到后，可点「立即同步」重试。

### 应用更新

正式版启动时检查 GitHub，应用在前台期间每小时再检查一次。也可从「设置 → 应用更新」手动检查。发现新版本后，应用优先下载与当前 Android 进程架构匹配的较小安装包，缺少匹配包时自动下载通用包 `app-release.apk`。下载中可取消，同一次运行中可手动重试。下载通过大小、SHA-256、包名、版本与签名校验后，应用在前台打开 Android 安装器，由你确认安装。首次更新如果需要授权，点「打开授权设置」，允许 Pi Muse 安装未知应用，返回后点「继续安装」。

首次安装或不确定设备架构时，请从 [Flutter Releases](https://github.com/yaotutu/pi-muse-flutter/releases) 下载 `app-release.apk`。发布页提供拆分包时，也可按设备架构选择 `arm64-v8a`、`armeabi-v7a` 或 `x86_64`。后续覆盖安装需要相同的包名和签名。若设备上装的是开发调试包，请先卸载调试版。卸载会清除该客户端的本机数据。

### 自动打包与发布

- 推送到 `main` 后，[发布流程](.github/workflows/release.yml) 递增 `pubspec.yaml` 的补丁版本和 Android 构建号，例如 `0.1.0+1` 变为 `0.1.1+2`。流程构建一个通用 APK 和三个拆分 APK，使用同一签名和构建号。分析、测试和 APK 校验通过后，流程推送版本提交及标签，将四个包上传到草稿，核对每个包的大小和 SHA-256 后再公开 GitHub Release。`pubspec.yaml` 的版本字段由发布流程维护。
- 手动运行 `release` 使用所选提交的现有版本，构建四个 APK 并保存在 Actions 产物中。版本提交、标签和正式发布由 `main` 的推送触发。
- GitHub 仓库需为 `yaotutu/pi-muse-flutter`，并让手机可匿名访问其 Releases 与 APK。仓库需允许发布流程的 `GITHUB_TOKEN` 写入 `main`、标签和 Releases。
- Flutter 的正式 APK 使用独立的发布签名，不复用 RN 客户端的 keystore。将 Base64 编码的 keystore、库密码、别名和密钥密码分别配置为仓库 Actions secrets `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS` 和 `ANDROID_KEY_PASSWORD`。妥善备份 keystore 和密码；后续版本必须使用同一把密钥，才能覆盖更新已安装的正式版。本地开发使用 Debug APK。

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

Open the drawer with the top-left menu button to switch sessions or tap **新建会话** (New session). The centered title displays the current session name. The bottom bar shows **聊天**, **待办**, **新闻**, and **设置**. To-do and News are not enabled yet; open Settings to reach the server connection. Your messages appear in bubbles on the right. Assistant replies appear in wide cards with Markdown formatting and the original line breaks. Replies stream into the conversation. When a file change needs approval, a banner appears below the app bar. Tap **查看修改** to read the full before and after text before approving or denying the change. If delivery is uncertain, tap **核对发送结果** to verify it before deciding whether to send again.

### View execution details

Tap **执行详情** (Execution details) in the top right of chat. **动态** (Activity) shows the current conversation's run status, tools, and subtasks, with a link to any pending approvals. **审批** (Approvals) lists pending file changes and past decisions. A historical preview shows the decision and the file operation result separately. **历史** (History) lists registered activities for the current conversation. Open one to see its goal, progress, result, and execution steps. A regular chat turn may have no activity record. Use Back to return to the conversation with the draft and any in-progress reply intact.

### Message actions

Use the buttons below a saved message to copy or quote it. Eligible messages also have Like, Dislike, and Bookmark buttons. Tap the bookmark to save it, then tap again to remove it. The server stores bookmarks independently of likes and dislikes. Highlighted icons show the current state. If the result is uncertain, first tap **核对反馈状态** (Check feedback status) below the message. The composer previews the removable quote. Add a follow-up or an attachment to send it with the next message.

During a reply started on this device, the composer shows **停止回复** (Stop reply). Enter a new message or add an attachment to switch to **停止并发送** (Stop and send). The app sends the next message after it confirms the stop and syncs history. If it cannot confirm the stop, the next message stays in the composer. If the first message was also unsaved, **切换未发送草稿** (Switch unsent drafts) lets you recover both.

### Manage conversations

In the drawer, open **更多操作** (More actions) next to a topic session to rename or delete it. Renaming keeps the history and draft. Deleting permanently removes its chat history and feedback. The confirmation shows its scheduled jobs and web monitors. You can delete those too or move them to the default session. Deleting the active session returns you to the default session.

### Settings

Open **设置** (Settings) from the bottom bar or the chat drawer. Both open the same Settings home, where you can use the bottom bar to switch back to **聊天** (Chat). Open **外观** (Appearance), **服务器连接** (Server connection), **短信同步** (SMS sync), or **应用更新** (App updates) from the list. Back returns to Settings home.

### Change the color palette

Open **设置 → 外观** (Settings → Appearance) and choose Indigo (default), Forest Green, Warm Brown, or Violet under **配色** (Color palette). The change takes effect immediately. The app remembers the last saved palette on this device and still follows the system's light or dark mode.

### Sync new SMS messages

Open **设置 → 短信同步** (Settings → SMS sync), turn on **同步新短信** (Sync new SMS messages), and grant Android permission to receive SMS. The app sends the original text and sender of new SMS messages to your connected Pi Muse server. HTTP connections transmit this data without encryption. Sync can continue in the background. While offline, the app encrypts pending messages on the device and resumes delivery when the network returns. Turning sync off or revoking permission pauses capture and uploads and keeps pending messages.

The page shows how many messages are pending and when the app last confirmed that the server accepted one. If the server has paused intake, tap **立即同步** (Sync now) once the server resumes intake. If the connection expires, reconnect from **服务器连接** (Server connection). Signing in again or updating the server address keeps pending messages. If delivery is uncertain, the app checks the server first. Once that check confirms a message is absent, tap **立即同步** to retry.

### App updates

The release build checks GitHub at startup and every hour while the app is in the foreground. To check manually, open **设置 → 应用更新** (Settings → App updates). When a new version is available, the app prefers the smaller APK that matches its running Android process architecture. If no matching APK is available, it downloads the universal `app-release.apk`. You can cancel the download and retry the same version manually during that app run. After checking the size, SHA-256, package ID, version and signing certificate, the app opens Android's installer in the foreground for you to confirm. If Android requires authorization, tap **打开授权设置** (Open permission settings), allow Pi Muse to install unknown apps, then return and tap **继续安装** (Continue installation).

For a first install or if you are unsure which architecture your device uses, download `app-release.apk` from [Flutter Releases](https://github.com/yaotutu/pi-muse-flutter/releases). When the release provides split APKs, you can choose the one for `arm64-v8a`, `armeabi-v7a` or `x86_64`. Android updates require the same package ID and signing certificate. If a development debug build is installed, uninstall it before installing the release APK. Uninstalling clears the client's local data.

### Automated builds and releases

- A push to `main` starts the [release workflow](.github/workflows/release.yml). It increments the patch version and Android build number in `pubspec.yaml`, for example from `0.1.0+1` to `0.1.1+2`. It builds one universal APK and three split APKs, all with the same signing key and build number. After analysis, tests and APK verification succeed, it pushes the version commit and tag and uploads all four APKs to a draft. It verifies the size and SHA-256 of each uploaded APK before publishing. The workflow maintains the version field.
- A manual `release` run builds all four APKs using the selected commit's current version and saves them as an Actions artifact. Pushes to `main` trigger version commits, tags and public releases.
- Use `yaotutu/pi-muse-flutter` as the GitHub repository and make its Releases and APKs available to phones without authentication. Allow the release workflow's `GITHUB_TOKEN` to write to `main`, tags and Releases.
- Flutter release APKs use a dedicated signing key, separate from the RN client's keystore. Configure the Base64-encoded keystore, store password, key alias and key password as Actions secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. Back up the keystore and password securely. Future releases need the same key to update installed release builds. Use the Debug APK for development.

### Send attachments

Tap **添加附件** on the left of the composer and choose images or text files in the Android file picker. Review or remove the files above the composer, then send them with or without a message. Each message can include up to four files and 8 MiB in total, with a shared limit of 100,000 bytes for text. Supported formats are PNG, JPEG, GIF, WebP, and valid UTF-8 text.

Attachments appear with the user message after sending. Tap an image to preview it. Text attachments show their name and size. Image understanding depends on the model configured on the server. If delivery is uncertain, tap **核对发送结果**. Once the app confirms the message was not saved, it restores the original files and text to that conversation's draft.

### Browse workspace files

Open the menu in the top-left corner of the chat and tap **工作区文件**. Every conversation shares the same workspace on the connected server. Tap a folder to open it, use **刷新目录** to refresh the list, and use Back to return to its parent.

Text files open as selectable source, including Markdown, HTML, and SVG. PNG, JPEG, GIF, and WebP images can be zoomed. Other binary files show their name and size. The server reads files up to 8 MiB. This screen provides browsing and previews.

### Run and check locally

Use Flutter 3.50.1, JDK 17 or a compatible version, Android SDK 36, and an Android emulator. Run the commands in the section above from this directory. An Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after forwarding the port with `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen with default graphics, retry with `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>`. Acceptance uses the backend from current source, a real model, and `/docs` rendered in a browser.
