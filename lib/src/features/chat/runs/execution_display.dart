String? executionText(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

String executionStatus(Object? status) => switch (status) {
  'queued' => '排队中',
  'running' => '进行中',
  'waiting_approval' => '等待审批',
  'waiting_user' => '等待用户补充',
  'awaiting_continuation' => '等待继续',
  'succeeded' || 'completed' => '已完成',
  'failed' => '失败',
  'stopped' => '已停止',
  'cancelled' => '已取消',
  'interrupted' => '已中断',
  'pending' => '待审批',
  'approved' => '已批准',
  'denied' => '已拒绝',
  'expired' => '已过期',
  _ => '状态未知',
};
