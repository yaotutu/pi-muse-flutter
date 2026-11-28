# 日程客户端实现约定

「日程」是客户端的独立功能页，事项的事实归服务端所有。本页记录客户端侧的模块划分、接口映射与一致性规则；面向用户的操作说明在服务端仓库的[用户手册](https://github.com/yaotutu/pi-muse/blob/main/docs/manual/agenda.md)。

## 模块划分

| 路径 | 职责 |
| --- | --- |
| `lib/src/features/agenda/agenda.dart` | 功能导出入口。 |
| `lib/src/features/agenda/agenda_client.dart` | 事项接口适配，只调用服务端契约里已有的端点。 |
| `lib/src/features/agenda/agenda_controller.dart` | 事项的本地状态：筛选、搜索、日历月份、待打开的事项，以及写操作后的回读。 |
| `lib/src/features/agenda/agenda_models.dart` | 事项、安排、截止、提醒的数据类型与解析。 |
| `lib/src/features/agenda/agenda_page.dart` | 日程页：上方月历，下方事项列表，两者读同一份服务端事实。 |
| `lib/src/features/agenda/agenda_item_page.dart` | 事项详情页，新建与编辑共用。 |
| `lib/src/shared/agenda_moment.dart` | 时间解析与展示文案。 |
| `lib/src/shared/agenda_receipt.dart` | 聊天事项回执模型，以及从消息和事件中取回执的规则。 |
| `lib/src/shared/workspace_events.dart` | 连接级通知事件记录，`AgendaController` 按事件名订阅同一条流。 |
| `lib/src/features/chat/agenda_receipt_card.dart` | 聊天里的事项卡片。 |

`lib/src/features/chat/` 依赖 `lib/src/shared/`，`lib/src/features/agenda/` 不反向依赖聊天模块；聊天只通过 `AgendaController.openItem` 请求打开事项。

## 接口映射

| 客户端动作 | 服务端接口 |
| --- | --- |
| 列表与日历读取 | `GET /api/agenda/items`，参数 `status`（`open`/`all`）、`q`、`from`、`to` |
| 打开一条事项 | `GET /api/agenda/items/:id` |
| 新建事项 | `POST /api/agenda/items` |
| 修改、完成、置顶 | `PATCH /api/agenda/items/:id`，只发送真正变化的字段 |
| 新建提醒 | `POST /api/agenda/items/:id/reminders` |
| 修改提醒 | `PATCH /api/agenda/items/:id/reminders/:reminderId` |
| 取消提醒 | `DELETE /api/agenda/items/:id/reminders/:reminderId` |

列表默认范围是未完成（`status=open`）；日历另读一次当月全部事项（`from` 为当月第一天，`to` 为下月第一天，排他）。选中某天时列表按 `from=当天`、`to=次日` 过滤。客户端不提供删除事项的入口，服务端也没有删除接口。

## 时间处理

- 只选到天的时间写 `{"type":"date","start":"YYYY-MM-DD"}`；带时刻写 `{"type":"time","start":"YYYY-MM-DDTHH:mm","timeZone":"Asia/Shanghai"}`。时区来自事项现有设置或实例，最终时刻由服务端解释。
- 提醒只写绝对提醒：给自然日和可选的 `HH:mm`；不写时刻时由服务端按 09:00 处理。
- 带偏移的时刻保留原钟点。UTC 时刻按 IANA 时区数据库换算和显示；日历归属统一按实例时区。

## 一致性规则

- **写入成功即回读**：写操作成功后先把服务端返回的事项合并进本地列表，再整体刷新一次；列表和日历始终反映服务端事实。
- **结果未明不重发**：超时、断网或 5xx 时不重发写请求，改为重新读取权威状态，并提示用户核对后再操作。
- **连接级失效通知**：通知流复用连接控制器已有的 `/api/events`，不另开连接。收到 `agenda_updated` 后整页失效重读；通知丢失由下次刷新兜底。
- **回执按 ID 去重**：聊天运行期间收到的 `CUSTOM`（`name: "agenda_receipt"`）回执与历史助手消息上的 `agendaReceipt` 是同一份回执，按 `id` 去重，只渲染一张卡片。事件里的 `value` 可能是对象，也可能是 JSON 字符串，两种都按同一份契约读取。
- **回执只是快照**：卡片只展示服务端返回的保存结果；「查看事项」和「修改时间」都按回执里的 `itemId` 打开同一条事项，读写以服务端保存的事实为准。

## 导航与深链

底栏「日程」是一级入口；聊天页始终保留在组件树上，切到日程时草稿和阅读位置不丢失。聊天卡片请求打开事项时，工作区切到「日程」并推入事项详情页；带「修改时间」的动作打开时定位到时间设置区。

## 验收

代码变更后执行 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`；涉及界面变化时在 `TB300FU` 实体平板上核对月历标记、列表筛选、新建与编辑提醒，以及聊天卡片跳转到同一条事项。
