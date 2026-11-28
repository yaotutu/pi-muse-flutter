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
- 客户端通过日期与时刻选择器新增和修改绝对提醒，取消选择器会放弃写入。相对提醒随安排或截止时间变动，可在客户端查看和取消。
- 带偏移的时刻保留原钟点。UTC 时刻按 IANA 时区数据库换算和显示。日历归属统一按实例时区。

## 一致性规则

- **写入成功即回读**：写操作成功后先把服务端返回的事项合并进本地列表，再整体刷新一次；列表和日历始终反映服务端事实。
- **结果未明不重发**：超时、断网或 5xx 时不重发写请求，改为重新读取权威状态，并提示用户核对后再操作。
- **连接级失效通知**：通知流复用连接控制器已有的 `/api/events`，不另开连接。收到 `agenda_updated` 后整页失效重读；通知丢失由下次刷新兜底。
- **回执按 ID 去重**：聊天运行期间收到的 `CUSTOM`（`name: "agenda_receipt"`）回执与历史助手消息上的 `agendaReceipt` 是同一份回执，按 `id` 去重，只渲染一张卡片。事件里的 `value` 是回执对象。
- **回执只是快照**：卡片只展示服务端返回的保存结果；「查看事项」和「修改时间」都按回执里的 `itemId` 打开同一条事项，读写以服务端保存的事实为准。

## 导航与深链

「日程」是一级入口；聊天页始终保留在组件树上，切到日程时草稿和阅读位置不丢失。聊天卡片请求打开事项时，工作区切到「日程」并推入事项详情页；带「修改时间」的动作打开时定位到时间设置区。

## 响应式布局

日程首页与详情按 Android 窗口尺寸分级和页面可用空间适配。

- **判定条件**。窗口宽至少 840dp、高至少 480dp 才启用双栏，并且日程页可用宽至少 680dp、详情页可用宽至少 640dp。窗口尺寸不受软键盘影响，页面宽度计入 96dp 左侧导航轨与安全区域。`TB300FU` 平板横屏约 962×601dp，两页走双栏，手机竖屏走单列。
- **日程页**。双栏时，左边 360dp 显示月历，右边显示筛选、搜索和事项列表，两栏独立滚动。窄屏月历限制高度，搜索期间让位给搜索结果。搜索可用键盘搜索键或搜索栏内的「应用搜索」按钮提交。右下角主操作是「新建事项」，搜索或键盘弹起时隐藏。
- **事项详情页**。双栏时左侧编辑标题与备注，右侧编辑安排、截止和提醒；窄屏使用单列滚动表单。两种布局的「保存」与「标记完成」都固定在底部，键盘弹起时仍可操作。详情读取失败时显示重试，不显示空白编辑表单。
- **状态与语义不变**：分栏只影响排版。筛选、搜索、选中日期、日历月份、置顶、完成与提醒的读写规则、写入字段和深链打开方式都与单列一致，编辑语义不变。

回归覆盖在 `test/features/agenda/agenda_page_test.dart`：横屏分栏、月历与列表独立滚动、详情页底部操作栏可达，以及改回竖屏后恢复单列。

## 验收

代码变更后执行 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`；涉及界面变化时在 `TB300FU` 实体平板上核对月历标记、列表筛选、新建与编辑提醒，以及聊天卡片跳转到同一条事项。
