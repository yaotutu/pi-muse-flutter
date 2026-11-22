# AGENTS.md — Pi Muse Flutter 开发规则

本仓库是独立的 Flutter Android 客户端。不依赖 Expo / React Native 源码、资源、构建或发布流程。位于 Pi Muse 本地工作区时，同时遵守工作区 `AGENTS.md` 及服务端协作指南；独立检出可以构建客户端，联调需配置可访问的 Pi Muse 服务端。

- 开发、构建和模拟器入口见 [README](README.md)。变更执行 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`；用户可见功能用当前真实后端、外部模型、Android 模拟器和浏览器渲染的 `/docs` 验收。需要用户现场体验时打开模拟器窗口，不只提供无窗口运行结果。
- `lib/main.dart` 管理连接和主题，`lib/src/api.dart` 管理 HTTP/SSE，`lib/src/chat.dart` 持有会话、草稿和运行，`lib/src/chat_page.dart` 负责呈现。服务端持有业务事实。以当前后端 `src/http/contracts/` 或对应运行版本的 `/docs`、`/openapi.json` 为准；AG-UI 聊天流与唯一 `/api/events` 通知流独立。
- 安全存储只保存服务地址和 Session Token，不保存 AccessKey。不记录凭据或真实用户会话。文件审批保留完整前后预览和逐次确认；结果未明先读取权威状态，不自动重发写入。未经授权不改变 Android 应用 ID、版本、CI 或发布配置。
