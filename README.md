# Pi Muse Flutter

## 简体中文

这是独立的 Flutter Android 客户端预览，不需要检出或运行 React Native 工程。应用使用独立包名 `com.pimuse.pi_muse_flutter`，通过 HTTP/SSE 连接 Pi Muse 服务端。打开后填写服务端根地址及访问密钥，点击「连接」。访问密钥用于换取 Session Token。连接成功后，可从主聊天进入会话列表、创建或切换会话。

点左上角打开侧边栏，选择会话或点「新建会话」。顶部居中显示当前会话名称。底栏显示「聊天」「待办」「新闻」「设置」；待办和新闻暂未启用，服务器连接从「设置」进入。用户消息显示在右侧气泡，助手回复是宽幅卡片，保留 Markdown 层级与原文换行。回复实时显示。有文件修改待确认时，顶栏下方才会出现提示，点击「查看修改」可核对修改前后全文，再选择批准或拒绝。如果发送结果不明，点「核对发送结果」后再决定是否发送。

### 查看执行详情

点聊天右上角的「执行详情」。**动态**显示当前会话的运行阶段、工具与子任务，有待审批时可跳转到对应列表。**审批**可查看待处理的文件修改和已处理的记录，历史预览会同时显示审批结果与实际写入回执。**历史**显示当前会话已登记的活动，点开可看目标、进度、结果与执行步骤。普通聊天可能没有活动记录。返回键回到聊天，草稿和正在生成的回复会保留。

### 操作消息

已保存的消息下方提供复制和引用按钮。可反馈的消息还会显示点赞和不喜欢，点亮的按钮表示当前反馈，再点一次即可撤销。结果不明时，点消息下方的「核对反馈状态」。引用会显示在输入框上方，可移除，写好追问或添加附件后随下一条消息发送。

本机正在生成回复时，输入框右侧显示「停止回复」。输入下一条或添加附件后，按钮变为「停止并发送」。客户端在确认上一轮停止并同步历史后发送下一条。如果无法确认，下一条保留在输入框。若上一条也未保存，可通过「切换未发送草稿」找回两条内容。

### 管理会话

打开左侧边栏，在专题会话的「更多操作」中可重命名或删除。重命名保留历史和草稿。删除会永久移除该会话的聊天历史和反馈，确认前会显示关联的定时任务和网页监控。有任务或监控时，可选择一并删除，或保留并转到默认会话。删除当前会话后会回到默认会话。

### 更换配色

打开「设置 → 外观」，在「配色」中选择靛蓝（默认）、森林绿、暖棕或紫色。点选后立即生效，下次打开应用时恢复上次保存的配色。设置仅保存在本机，浅色和深色仍自动跟随系统。

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

Use the buttons below a saved message to copy or quote it. Eligible messages also have Like and Dislike buttons. The active reaction is highlighted. Tap it again to clear it. If the result is uncertain, tap **核对反馈状态** (Check feedback status) below the message. The composer previews the removable quote. Add a follow-up or an attachment to send it with the next message.

During a reply started on this device, the composer shows **停止回复** (Stop reply). Enter a new message or add an attachment to switch to **停止并发送** (Stop and send). The app sends the next message after it confirms the stop and syncs history. If it cannot confirm the stop, the next message stays in the composer. If the first message was also unsaved, **切换未发送草稿** (Switch unsent drafts) lets you recover both.

### Manage conversations

In the drawer, open **更多操作** (More actions) next to a topic session to rename or delete it. Renaming keeps the history and draft. Deleting permanently removes its chat history and feedback. The confirmation shows its scheduled jobs and web monitors. You can delete those too or move them to the default session. Deleting the active session returns you to the default session.

### Change the color palette

Open **设置 → 外观** (Settings → Appearance) and choose Indigo (default), Forest Green, Warm Brown, or Violet under **配色** (Color palette). The change takes effect immediately. The app remembers the last saved palette on this device and still follows the system's light or dark mode.

### Send attachments

Tap **添加附件** on the left of the composer and choose images or text files in the Android file picker. Review or remove the files above the composer, then send them with or without a message. Each message can include up to four files and 8 MiB in total, with a shared limit of 100,000 bytes for text. Supported formats are PNG, JPEG, GIF, WebP, and valid UTF-8 text.

Attachments appear with the user message after sending. Tap an image to preview it. Text attachments show their name and size. Image understanding depends on the model configured on the server. If delivery is uncertain, tap **核对发送结果**. Once the app confirms the message was not saved, it restores the original files and text to that conversation's draft.

### Browse workspace files

Open the menu in the top-left corner of the chat and tap **工作区文件**. Every conversation shares the same workspace on the connected server. Tap a folder to open it, use **刷新目录** to refresh the list, and use Back to return to its parent.

Text files open as selectable source, including Markdown, HTML, and SVG. PNG, JPEG, GIF, and WebP images can be zoomed. Other binary files show their name and size. The server reads files up to 8 MiB. This screen provides browsing and previews.

### Run and check locally

Use Flutter 3.50.1, JDK 17 or a compatible version, Android SDK 36, and an Android emulator. Run the commands in the section above from this directory. An Android emulator can reach the host server at `http://10.0.2.2:12330`, or at `http://127.0.0.1:12330` after forwarding the port with `adb reverse tcp:12330 tcp:12330`. If the emulator stalls at the splash screen with default graphics, retry with `flutter run --no-enable-impeller --enable-software-rendering -d <android-device-id>`. Acceptance uses the backend from current source, a real model, and `/docs` rendered in a browser.
