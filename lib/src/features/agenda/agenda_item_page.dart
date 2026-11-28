import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../network/api.dart';
import 'agenda_client.dart';
import 'agenda_controller.dart';
import 'agenda_models.dart';

/// 事项详情页。新建和编辑共用，编辑时按 ID 回读服务端保存的事实。
class AgendaItemPage extends StatefulWidget {
  const AgendaItemPage({
    super.key,
    required this.agenda,
    this.itemId,
    this.focusTime = false,
  });

  final AgendaController agenda;
  final String? itemId;
  final bool focusTime;

  @override
  State<AgendaItemPage> createState() => _AgendaItemPageState();
}

class _AgendaItemPageState extends State<AgendaItemPage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _timeSection = GlobalKey();

  /// 宽横屏分栏的最小可用宽度。
  static const _wideMinWidth = 640.0;

  /// 宽横屏分栏的最小窗口高度。用窗口高度判断，避免软键盘弹起时布局来回切换。
  static const _wideMinHeight = 400.0;

  AgendaItem? _item;
  bool _loading = true;
  bool _saving = false;
  bool _scheduleChanged = false;
  bool _dueChanged = false;
  String? _error;
  String? _readError;
  int _readGeneration = 0;
  int _invalidations = 0;
  Timer? _reminderTimer;

  DateTime? _scheduleDay;
  TimeOfDay? _scheduleTime;
  DateTime? _dueDay;
  TimeOfDay? _dueTime;

  bool get _creating => widget.itemId == null;

  @override
  void initState() {
    super.initState();
    widget.agenda.addListener(_onChanged);
    if (_creating) {
      _loading = false;
      return;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.agenda.removeListener(_onChanged);
    _reminderTimer?.cancel();
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_readGeneration;
    try {
      final item = await widget.agenda.read(widget.itemId!);
      if (!mounted || generation != _readGeneration) return;
      final firstRead = _item == null;
      setState(() {
        _loading = false;
        _readError = null;
        final previous = _item;
        if (previous == null || _title.text == previous.title) {
          _title.text = item.title;
        }
        if (previous == null || _notes.text == (previous.notes ?? '')) {
          _notes.text = item.notes ?? '';
        }
        _applyItemTimes(item);
        _item = item;
      });
      _scheduleReminderRefresh(item);
      if (firstRead && widget.focusTime) _focusTimeSection();
    } catch (failure) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _loading = false;
        _readError = agendaErrorMessage(failure);
      });
    }
  }

  /// 提醒到点后回读一次，提醒触发状态由服务端判定。
  void _scheduleReminderRefresh(AgendaItem item) {
    _reminderTimer?.cancel();
    DateTime? next;
    for (final reminder in item.reminders) {
      if (!reminder.pending) continue;
      final instant = reminder.moment?.instant;
      if (instant == null) continue;
      if (next == null || instant.isBefore(next)) next = instant;
    }
    if (next == null) return;
    final delay = next.difference(DateTime.now().toUtc());
    if (delay.isNegative) return;
    _reminderTimer = Timer(delay + const Duration(seconds: 1), () {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  /// 从聊天卡片进入时，直接定位到时间设置。
  void _focusTimeSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _timeSection.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
    });
  }

  void _applyItemTimes(AgendaItem item) {
    if (!_scheduleChanged) {
      final schedule = item.schedule?.moment;
      _scheduleDay = schedule?.wallClock;
      _scheduleTime = schedule != null && schedule.hasTime
          ? TimeOfDay.fromDateTime(schedule.wallClock)
          : null;
    }
    if (!_dueChanged) {
      final due = item.due?.moment;
      _dueDay = due?.wallClock;
      _dueTime = due != null && due.hasTime
          ? TimeOfDay.fromDateTime(due.wallClock)
          : null;
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    // 服务端通知事项变更时回读权威状态，避免页面停留在旧快照。
    if (widget.agenda.invalidationCount != _invalidations) {
      _invalidations = widget.agenda.invalidationCount;
      if (!_creating) unawaited(_load());
    }
  }

  Future<void> _pickScheduleDay() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _scheduleDay ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (day == null || !mounted) return;
    setState(() {
      _scheduleDay = day;
      _scheduleChanged = true;
    });
  }

  Future<void> _pickScheduleTime() async {
    final day = _scheduleDay;
    if (day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _scheduleTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduleTime = time;
      _scheduleChanged = true;
    });
  }

  Future<void> _pickDueDay() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _dueDay ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (day == null || !mounted) return;
    setState(() {
      _dueDay = day;
      _dueChanged = true;
    });
  }

  Future<void> _pickDueTime() async {
    final day = _dueDay;
    if (day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _dueTime = time;
      _dueChanged = true;
    });
  }

  /// 安排时间的写入内容。日期单独保存，本地时刻交给服务端解释。
  Json? _schedulePayload() {
    final day = _scheduleDay;
    if (day == null) return null;
    final time = _scheduleTime;
    if (time == null) {
      return {'type': 'date', 'start': formatAgendaDate(day)};
    }
    final zone = _item?.schedule?.timeZone ?? widget.agenda.instanceZone;
    return {
      'type': 'time',
      'start': formatAgendaLocalTimestamp(day, time),
      'timeZone': ?zone,
    };
  }

  /// 截止时间的写入内容。
  Json? _duePayload() {
    final day = _dueDay;
    if (day == null) return null;
    final time = _dueTime;
    if (time == null) {
      return {'type': 'date', 'value': formatAgendaDate(day)};
    }
    final zone = _item?.due?.timeZone ?? widget.agenda.instanceZone;
    return {
      'type': 'time',
      'value': formatAgendaLocalTimestamp(day, time),
      'timeZone': ?zone,
    };
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final schedule = _schedulePayload();
    final due = _duePayload();
    final notes = _notes.text.trim();
    final item = _creating
        ? await widget.agenda.create(
            title: title,
            notes: notes,
            schedule: schedule,
            due: due,
          )
        : await widget.agenda.update(
            widget.itemId!,
            title: title == _item?.title ? null : title,
            notes: notes == (_item?.notes ?? '') ? null : notes,
            clearNotes: notes.isEmpty && _item?.notes != null,
            schedule: _scheduleChanged ? schedule : null,
            clearSchedule: _scheduleChanged && schedule == null,
            due: _dueChanged ? due : null,
            clearDue: _dueChanged && due == null,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (item == null) {
      setState(() => _error = widget.agenda.notice);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _toggleCompleted() async {
    final item = _item;
    if (item == null) return;
    final updated = await widget.agenda.setCompleted(item, !item.completed);
    if (!mounted || updated == null) return;
    setState(() => _item = updated);
    _scheduleReminderRefresh(updated);
  }

  Future<void> _togglePinned() async {
    final item = _item;
    if (item == null) return;
    final updated = await widget.agenda.setPinned(item, !item.pinned);
    if (!mounted || updated == null) return;
    setState(() => _item = updated);
    _scheduleReminderRefresh(updated);
  }

  Future<void> _addReminder() async {
    final item = _item;
    if (item == null) return;
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    final updated = await widget.agenda.addReminder(
      item.id,
      day: day,
      time:
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}',
    );
    if (!mounted || updated == null) return;
    setState(() => _item = updated);
    _scheduleReminderRefresh(updated);
  }

  Future<void> _editReminder(AgendaReminder reminder) async {
    final item = _item;
    final moment = reminder.moment;
    if (item == null || moment == null) return;
    final day = await showDatePicker(
      context: context,
      initialDate: moment.wallClock,
      firstDate: DateTime(DateTime.now().year - 20),
      lastDate: DateTime(DateTime.now().year + 20),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(moment.wallClock),
    );
    if (time == null || !mounted) return;
    final updated = await widget.agenda.updateReminder(
      item.id,
      reminder.id,
      day: day,
      time:
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}',
    );
    if (!mounted || updated == null) return;
    setState(() => _item = updated);
    _scheduleReminderRefresh(updated);
  }

  Future<void> _cancelReminder(AgendaReminder reminder) async {
    final item = _item;
    if (item == null) return;
    final updated = await widget.agenda.deleteReminder(item.id, reminder.id);
    if (!mounted || updated == null) return;
    setState(() => _item = updated);
    _scheduleReminderRefresh(updated);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final readError = _readError;
    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? '新建事项' : '事项详情'),
        actions: [
          if (item != null && _readError == null)
            IconButton(
              tooltip: item.pinned ? '取消置顶' : '置顶',
              icon: Icon(
                item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: _togglePinned,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : readError != null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(readError, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _loading = true);
                          unawaited(_load());
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = _isWide(constraints);
                  return Column(
                    children: [
                      Expanded(
                        child: wide
                            ? _buildWideLayout(context)
                            : _buildNarrowLayout(context),
                      ),
                      _buildActionBar(context),
                    ],
                  );
                },
              ),
      ),
    );
  }

  /// 宽横屏才左右分栏：宽度按实际可用空间判断，方向与高度按窗口判断，
  /// 避免竖屏宽窗口和软键盘弹起时把分栏布局改回单列。
  bool _isWide(BoxConstraints constraints) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height &&
        size.height >= _wideMinHeight &&
        constraints.maxWidth >= _wideMinWidth;
  }

  /// 窄屏与竖屏布局：单列滚动表单。
  Widget _buildNarrowLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TextField(
          controller: _title,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '备注',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _scheduleSection(),
        const SizedBox(height: 12),
        _dueSection(),
        const SizedBox(height: 12),
        _reminderSection(),
        if (widget.agenda.instanceZone case final zone?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '服务端时区：$zone',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// 宽横屏布局：左侧标题与备注，右侧安排、截止与提醒，
  /// 保存与完成按钮固定在底部，随时可点。
  Widget _buildWideLayout(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 4,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        VerticalDivider(
          key: const Key('agenda-item-pane-divider'),
          width: 1,
          thickness: 1,
          color: colors.outlineVariant,
        ),
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _scheduleSection(),
                const SizedBox(height: 12),
                _dueSection(),
                const SizedBox(height: 12),
                _reminderSection(),
                if (widget.agenda.instanceZone case final zone?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '服务端时区：$zone',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 固定底部操作栏，两种布局下都不必滚动到表单末尾。
  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = _item;
    return Material(
      color: colors.surface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: [
                if (item != null)
                  OutlinedButton(
                    onPressed: _saving ? null : _toggleCompleted,
                    child: Text(item.completed ? '重新打开' : '标记完成'),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '正在保存…' : '保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleSection() {
    return _MomentSection(
      key: _timeSection,
      title: '安排时间',
      icon: Icons.event,
      day: _scheduleDay,
      time: _scheduleTime,
      onPickDay: _pickScheduleDay,
      onPickTime: _pickScheduleTime,
      onClear: () => setState(() {
        _scheduleChanged = true;
        _scheduleDay = null;
        _scheduleTime = null;
      }),
    );
  }

  Widget _dueSection() {
    return _MomentSection(
      title: '截止时间',
      icon: Icons.flag_outlined,
      day: _dueDay,
      time: _dueTime,
      onPickDay: _pickDueDay,
      onPickTime: _pickDueTime,
      onClear: () => setState(() {
        _dueChanged = true;
        _dueDay = null;
        _dueTime = null;
      }),
    );
  }

  Widget _reminderSection() {
    return _ReminderSection(
      item: _item,
      onAdd: _addReminder,
      onEdit: _editReminder,
      onCancel: _cancelReminder,
    );
  }
}

/// 安排或截止时间的编辑区。
class _MomentSection extends StatelessWidget {
  const _MomentSection({
    super.key,
    required this.title,
    required this.icon,
    required this.day,
    required this.time,
    required this.onPickDay,
    required this.onPickTime,
    required this.onClear,
  });

  final String title;
  final IconData icon;
  final DateTime? day;
  final TimeOfDay? time;
  final VoidCallback onPickDay;
  final VoidCallback onPickTime;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final text = day == null
        ? '未设置'
        : time == null
        ? localizations.formatMediumDate(day!)
        : '${localizations.formatMediumDate(day!)} '
              '${localizations.formatTimeOfDay(time!, alwaysUse24HourFormat: true)}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelMedium),
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: day == null
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onPickDay, child: const Text('日期')),
            if (day != null)
              TextButton(onPressed: onPickTime, child: const Text('时间')),
            if (day != null)
              IconButton(
                tooltip: '清除',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// 提醒列表。
class _ReminderSection extends StatelessWidget {
  const _ReminderSection({
    required this.item,
    required this.onAdd,
    required this.onEdit,
    required this.onCancel,
  });

  final AgendaItem? item;
  final VoidCallback onAdd;
  final ValueChanged<AgendaReminder> onEdit;
  final ValueChanged<AgendaReminder> onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reminders = item?.reminders ?? const <AgendaReminder>[];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alarm, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text('提醒', style: theme.textTheme.labelMedium)),
                TextButton(
                  onPressed: item == null ? null : onAdd,
                  child: const Text('添加提醒'),
                ),
              ],
            ),
            if (item == null)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  '保存后可以添加提醒',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            else if (reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 28, bottom: 4),
                child: Text(
                  '还没有提醒',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            for (final reminder in reminders)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  reminder.pending
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                title: Text(
                  reminder.moment == null
                      ? '提醒'
                      : formatAgendaMoment(context, reminder.moment!),
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  reminder.reminderStatus?.label ?? reminder.status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                trailing: reminder.pending
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (reminder.reminderKind ==
                              AgendaReminderKind.absolute)
                            IconButton(
                              tooltip: '修改提醒',
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () => onEdit(reminder),
                            ),
                          IconButton(
                            tooltip: '取消提醒',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => onCancel(reminder),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
