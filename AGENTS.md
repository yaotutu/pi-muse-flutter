# AGENTS.md — Pi Muse Flutter 开发规则

本仓库是独立的 Flutter Android 客户端。不依赖 Expo / React Native 源码、资源、构建或发布流程。位于 Pi Muse 本地工作区时，同时遵守工作区 `AGENTS.md` 及服务端协作指南；独立检出可以构建客户端，联调需配置可访问的 Pi Muse 服务端。

## 目录与状态所有权

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart`、`lib/src/app/` | Flutter 启动入口、连接生命周期、主题、工作区导航、自适应布局和设置入口。 |
| `lib/src/network/` | HTTP 传输、服务地址校验、响应与 SSE 解码。 |
| `lib/src/features/chat/` | 连接级聊天控制器、会话目录与历史、草稿、消息与附件、运行和审批。每个连接由控制器持有一条 `/api/events`，AG-UI 聊天 SSE 按运行管理。 |
| `lib/src/features/{connection,appearance,app-update}/` | 服务器连接、外观和应用更新的页面及相关操作。 |
| `lib/src/features/{mcp,subagents,sms-sync,workspace-files}/` | 按功能维护 Pi Muse 客户端页面及接口适配。MCP 设置通过 Pi Muse HTTP API 管理服务端配置。 |
| `lib/src/shared/` | 跨功能复用的基础工具。 |
| `android/app/src/main/`、`android/app/src/test/` | Kotlin 桥接按 `sms`、`attachments`、`appupdate` 分包。`MainActivity` 与 Manifest、WorkManager 引用的组件保留原类身份。 |
| `test/{app,network,features,support}/` | 应用导航、协议和功能回归测试与共享测试夹具。 |
| `.github/`、`tools/` | CI、Android 发布和版本脚本。细节见[Android 发布指南](docs/android-release.md)。 |
| `README.md`、`docs/` | 中英文安装与本地运行入口、专项工程文档。 |

`app/` 组装功能页面，不把设置路由、分栏状态等应用级职责放进聊天页。功能页面、接口适配和数据类型按功能就近维护，不反向依赖 `app/`；`network/` 与 `shared/` 不依赖功能页面。MCP 协议、连接与执行由服务端实现。

Dart 文件采用 `snake_case.dart`，普通目录与 Markdown 文件用 ASCII 小写 kebab-case，Android 平台文件遵循现有 Gradle、Android 和 Kotlin 命名。依赖和 SDK 约束以 `pubspec.yaml`、锁文件、Gradle 与 CI 为准。构建产物留在 `build/` 等已有忽略目录，签名与实例数据留在本地。

## 接入边界

- 在工作区先读服务端 `docs/client-integration-guide.md`、`docs/client-notes.md` 及收件箱相关条目。联调时查目标实例 `/api/health`、`/docs`、`/openapi.json`。源码开发以服务端 `src/http/contracts/` 为协议定义，按实例版本核对已部署行为。
- 服务端持有会话历史、运行状态和业务事实。连接级缓存、未发送草稿与本机 UI 偏好由客户端管理。更换连接或重置历史时，按连接代次、`sessionId` 与 `piSessionId` 隔离迟到响应。通知订阅由连接控制器统一分发。
- 安全存储只保存服务地址和 Session Token，AccessKey 用于换取 Token。Authorization 通过请求头传递。不记录凭据或真实用户会话。审批操作展示完整不可变预览并由用户逐次确认，分别呈现决定与执行状态。写入结果未明时先查权威状态。

## 开发与验收

| 命令 | 用途 |
| --- | --- |
| `flutter pub get` | 安装依赖。 |
| `flutter analyze` | Dart 静态检查。 |
| `flutter test` | Flutter 单元与 Widget 测试。 |
| `flutter build apk --debug` | 构建 Android Debug APK。 |
| `flutter run -d <android-device-id>` | 在指定设备或模拟器运行。 |
| `cd android && ./gradlew :app:testDebugUnitTest` | 先完成 Debug APK 构建以准备本地 Gradle 包装器，再运行 Android 原生单元测试。 |

在本仓库执行上述命令。代码变更完成 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`，Kotlin 变更按影响覆盖原生测试。用户可见功能使用当前真实后端、外部模型、Android 设备和实际浏览器渲染的 `/docs` 验收。

Android 设备验收优先使用用户提供的 `TB300FU` 实体平板。测试前用 `adb devices -l` 确认平板处于 `device` 状态，运行和测试命令显式指定该平板。只要平板能连接，就不启动或使用模拟器；仅在确认平板无法连接时，才回退到模拟器，并在验收说明中注明。设备连接与回退方法见 [README](README.md)。

功能变化同步更新受影响的 README 和对应工程文档。公共手册中受影响的中英文页面按工作区文档规范同步。工程文档整理检查差异、引用、命名和规则一致性。版本由 CI 管理，手动改应用 ID、版本、签名、CI 或正式发布配置需明确授权。

已验收的功能或修复仅暂存本任务文件，清理临时测试数据后按[Android 发布指南](docs/android-release.md)提交和推送。
