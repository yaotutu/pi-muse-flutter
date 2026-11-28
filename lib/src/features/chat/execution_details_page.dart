import 'package:material_ui/material_ui.dart';

import 'approvals/approvals_tab.dart';
import 'chat_controller.dart';
import 'runs/run_history_tab.dart';
import 'runs/session_schedules_tab.dart';

class ExecutionDetailsPage extends StatefulWidget {
  const ExecutionDetailsPage({
    super.key,
    required this.chat,
    required this.sessionId,
    required this.openApproval,
  });

  final ChatController chat;
  final String sessionId;
  final void Function(BuildContext, String, Approval?) openApproval;

  @override
  State<ExecutionDetailsPage> createState() => _ExecutionDetailsPageState();
}

class _ExecutionDetailsPageState extends State<ExecutionDetailsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _visited = {0};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_visited.add(_tabs.index)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openApprovalById(String id) =>
      widget.openApproval(context, id, widget.chat.approvals[id]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('会话详情'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: '执行记录'),
          Tab(text: '审批'),
          Tab(text: '定时任务'),
        ],
      ),
    ),
    body: SafeArea(
      top: false,
      child: TabBarView(
        controller: _tabs,
        children: [
          RunHistoryTab(
            chat: widget.chat,
            sessionId: widget.sessionId,
            onOpenPendingTab: () => _tabs.animateTo(1),
            onOpenApproval: _openApprovalById,
          ),
          if (_visited.contains(1))
            ApprovalsTab(
              chat: widget.chat,
              sessionId: widget.sessionId,
              onOpen: (id, pending) =>
                  widget.openApproval(context, id, pending),
            )
          else
            const SizedBox(),
          if (_visited.contains(2))
            SessionSchedulesTab(chat: widget.chat, sessionId: widget.sessionId)
          else
            const SizedBox(),
        ],
      ),
    ),
  );
}
