import '../network/api.dart';

/// 连接级通知事件。客户端每个连接只有一条 `/api/events`，各功能按事件名订阅。
typedef WorkspaceEvent = ({String name, Json data});
