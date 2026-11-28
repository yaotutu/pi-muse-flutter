import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'agenda_controller.dart';
import 'agenda_item_page.dart';
import 'agenda_models.dart';

/// 日程页。上面是月历，下面是事项列表，两者读同一份服务端事实。
class AgendaPage extends StatefulWidget {
  const AgendaPage({
    super.key,
    required this.agenda,
    required this.keyboardVisible,
    required this.showCalendarPane,
  });

  final AgendaController agenda;

  // 外壳统一处理键盘避让；这里接收外壳移除 viewInsets 之前的状态。
  final bool keyboardVisible;
  final bool showCalendarPane;

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  final _search = TextEditingController();
  bool _searching = false;
  String? _opening;

  // 7 个日期列各预留 48dp，另加两侧留白。
  static const _calendarPaneWidth = 360.0;

  AgendaController get _agenda => widget.agenda;
  bool get _showCreate => !_searching && !widget.keyboardVisible;

  @override
  void initState() {
    super.initState();
    _agenda.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_agenda.refresh());
      _openFocus();
    });
  }

  @override
  void dispose() {
    _agenda.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _openFocus();
  }

  /// 聊天里的事项卡片要求打开某个事项时，切到这个页面并进入详情。
  void _openFocus() {
    final id = _agenda.focusItemId;
    if (id == null || id == _opening) return;
    _opening = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusTime = _agenda.focusTime;
      _agenda.clearFocus();
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute(
              builder: (_) => AgendaItemPage(
                agenda: _agenda,
                itemId: id,
                focusTime: focusTime,
              ),
            ),
          )
          .then((_) {
            // 详情页关闭后允许再次打开同一个事项。
            if (mounted) setState(() => _opening = null);
          });
    });
  }

  void _openItem(AgendaItem item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AgendaItemPage(agenda: _agenda, itemId: item.id),
      ),
    );
  }

  void _createItem() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AgendaItemPage(agenda: _agenda)),
    );
  }

  Future<void> _searchItems(String value) async {
    await _agenda.setQuery(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程'),
        actions: [
          IconButton(
            tooltip: _searching ? '关闭搜索' : '搜索事项',
            icon: Icon(_searching ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                unawaited(_agenda.setQuery(''));
              }
            },
          ),
          IconButton(
            tooltip: '刷新日程',
            icon: const Icon(Icons.refresh),
            onPressed: () => _agenda.refresh(),
          ),
        ],
      ),
      floatingActionButton: _showCreate
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _createItem,
              icon: const Icon(Icons.add),
              label: const Text('新建事项'),
            )
          : null,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              widget.showCalendarPane && constraints.maxWidth >= 680
              ? _buildWideLayout(context)
              : _buildNarrowLayout(context, constraints.maxHeight),
        ),
      ),
    );
  }

  /// 窄屏与竖屏布局：上方月历，下方筛选与列表。
  Widget _buildNarrowLayout(BuildContext context, double availableHeight) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_searching) _buildSearchField(),
        if (_showCreate)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: availableHeight * 0.57),
            child: SingleChildScrollView(
              child: _AgendaCalendarCard(
                month: _agenda.month,
                selectedDay: _agenda.selectedDay,
                items: _agenda.monthItems,
                instanceZone: _agenda.instanceZone,
                onMonthChanged: _agenda.setMonth,
                onSelectDay: _agenda.selectDay,
              ),
            ),
          ),
        _buildFilterBar(),
        _buildNotice(),
        Expanded(child: _buildList(context)),
      ],
    );
  }

  /// 宽横屏布局：左侧紧凑月历，右侧筛选、搜索与列表，两侧各自滚动。
  Widget _buildWideLayout(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _calendarPaneWidth,
          child: SingleChildScrollView(
            child: _AgendaCalendarCard(
              month: _agenda.month,
              selectedDay: _agenda.selectedDay,
              items: _agenda.monthItems,
              instanceZone: _agenda.instanceZone,
              onMonthChanged: _agenda.setMonth,
              onSelectDay: _agenda.selectDay,
            ),
          ),
        ),
        VerticalDivider(
          key: const Key('agenda-pane-divider'),
          width: 1,
          thickness: 1,
          color: colors.outlineVariant,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searching) _buildSearchField(),
              _buildFilterBar(),
              _buildNotice(),
              Expanded(child: _buildList(context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SearchBar(
        controller: _search,
        autoFocus: true,
        textInputAction: TextInputAction.search,
        hintText: '搜索事项标题或备注',
        elevation: const WidgetStatePropertyAll(0),
        trailing: [
          IconButton(
            tooltip: '应用搜索',
            icon: const Icon(Icons.search),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              unawaited(_searchItems(_search.text));
            },
          ),
        ],
        onSubmitted: _searchItems,
      ),
    );
  }

  Widget _buildFilterBar() {
    return _AgendaFilterBar(
      scope: _agenda.scope,
      selectedDay: _agenda.selectedDay,
      onScopeChanged: _agenda.setScope,
      onClearDay: () => _agenda.selectDay(null),
    );
  }

  /// 错误与提示。读失败且列表为空时由列表自己展示重试入口。
  Widget _buildNotice() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final String text;
    if (_agenda.notice case final notice?) {
      text = notice;
    } else if (_agenda.items.isNotEmpty && _agenda.error != null) {
      text = _agenda.error!;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = _agenda.error;
    final emptyPadding = EdgeInsets.fromLTRB(24, 12, 24, _showCreate ? 64 : 12);
    if (error != null && _agenda.items.isEmpty) {
      return Padding(
        padding: emptyPadding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _agenda.refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_agenda.loading && _agenda.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_agenda.items.isEmpty) {
      return Padding(
        padding: emptyPadding,
        child: Center(
          child: Text(
            _agenda.query.isNotEmpty
                ? '没有符合搜索条件的事项'
                : _agenda.selectedDay == null
                ? '还没有事项'
                : '这一天没有事项',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 4, 12, _showCreate ? 88 : 24),
      itemCount: _agenda.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final item = _agenda.items[index];
        return _AgendaItemTile(
          item: item,
          onOpen: () => _openItem(item),
          onToggleCompleted: (value) => _agenda.setCompleted(item, value),
          onTogglePinned: () => _agenda.setPinned(item, !item.pinned),
        );
      },
    );
  }
}

/// 日历上标记事项的类型。
enum _CalendarMark { schedule, due, reminder }

/// 月历。展示当月有安排、截止和提醒的事项。
class _AgendaCalendarCard extends StatelessWidget {
  const _AgendaCalendarCard({
    required this.month,
    required this.selectedDay,
    required this.items,
    required this.instanceZone,
    required this.onMonthChanged,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime? selectedDay;
  final List<AgendaItem> items;

  /// 服务端实例时区的偏移。日程归属按此时区计算。
  final String? instanceZone;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime?> onSelectDay;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final marks = _marksByDay();
    final today = DateTime.now();
    final scaler = MediaQuery.textScalerOf(context);
    final dayStyle = theme.textTheme.labelMedium!;
    final localizations = MaterialLocalizations.of(context);
    final fontSize = dayStyle.fontSize ?? 12;
    final numberHeight = scaler.scale(fontSize) * (dayStyle.height ?? 1.33);
    // 日期数字随系统字号增高，同时为三个状态图标保留独立一行。
    final cellHeight = (numberHeight + 18).clamp(48.0, double.infinity);
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((leading + days) / 7).ceil() * 7;
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上个月',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      onMonthChanged(DateTime(month.year, month.month - 1)),
                ),
                Expanded(
                  child: Text(
                    '${month.year}年${month.month}月',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      onMonthChanged(DateTime(month.year, month.month + 1)),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: cellHeight,
              ),
              itemCount: cells,
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                if (dayNumber < 1 || dayNumber > days) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(month.year, month.month, dayNumber);
                final selected =
                    selectedDay != null &&
                    DateUtils.isSameDay(day, selectedDay!);
                final isToday = DateUtils.isSameDay(day, today);
                final dayMarks = marks[day] ?? const <_CalendarMark>{};
                return Semantics(
                  label: [
                    localizations.formatFullDate(day),
                    if (isToday) '今天',
                    for (final mark in _CalendarMark.values)
                      if (dayMarks.contains(mark)) _markLabel(mark),
                  ].join('，'),
                  selected: selected,
                  button: true,
                  child: InkWell(
                    onTap: () => onSelectDay(selected ? null : day),
                    excludeFromSemantics: true,
                    borderRadius: BorderRadius.circular(16),
                    child: ExcludeSemantics(
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: selected ? colors.primaryContainer : null,
                          border: isToday && !selected
                              ? Border.all(color: colors.primary)
                              : null,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: dayStyle.copyWith(
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                                fontWeight: isToday || selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            SizedBox(
                              height: 12,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final mark in _CalendarMark.values)
                                    if (dayMarks.contains(mark))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 0.5,
                                        ),
                                        child: Icon(
                                          _markIcon(mark),
                                          size: 11,
                                          color: _markColor(mark, colors),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  onTap: () => onSelectDay(selected ? null : day),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Wrap(
                alignment: WrapAlignment.center,
                runSpacing: 4,
                children: [
                  for (final mark in _CalendarMark.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _markIcon(mark),
                            size: 12,
                            color: _markColor(mark, colors),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _markLabel(mark),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<DateTime, Set<_CalendarMark>> _marksByDay() {
    final marks = <DateTime, Set<_CalendarMark>>{};
    void mark(DateTime day, _CalendarMark kind) {
      final key = DateTime(day.year, day.month, day.day);
      marks.putIfAbsent(key, () => <_CalendarMark>{}).add(kind);
    }

    for (final item in items) {
      for (final day in item.scheduleDays(instanceZone: instanceZone)) {
        mark(day, _CalendarMark.schedule);
      }
      for (final day in item.dueDays(instanceZone: instanceZone)) {
        mark(day, _CalendarMark.due);
      }
      for (final day in item.reminderDays(instanceZone: instanceZone)) {
        mark(day, _CalendarMark.reminder);
      }
    }
    return marks;
  }

  static IconData _markIcon(_CalendarMark mark) => switch (mark) {
    _CalendarMark.schedule => Icons.event,
    _CalendarMark.due => Icons.flag_outlined,
    _CalendarMark.reminder => Icons.alarm,
  };

  static Color _markColor(_CalendarMark mark, ColorScheme colors) =>
      switch (mark) {
        _CalendarMark.schedule => colors.primary,
        _CalendarMark.due => colors.error,
        _CalendarMark.reminder => colors.tertiary,
      };

  static String _markLabel(_CalendarMark mark) => switch (mark) {
    _CalendarMark.schedule => '安排',
    _CalendarMark.due => '截止',
    _CalendarMark.reminder => '提醒',
  };
}

/// 列表筛选栏。
class _AgendaFilterBar extends StatelessWidget {
  const _AgendaFilterBar({
    required this.scope,
    required this.selectedDay,
    required this.onScopeChanged,
    required this.onClearDay,
  });

  final AgendaScope scope;
  final DateTime? selectedDay;
  final ValueChanged<AgendaScope> onScopeChanged;
  final VoidCallback onClearDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.start,
        overflowSpacing: 4,
        spacing: 12,
        children: [
          SegmentedButton<AgendaScope>(
            segments: [
              for (final value in AgendaScope.values)
                ButtonSegment(value: value, label: Text(value.label)),
            ],
            selected: {scope},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onScopeChanged(selection.first),
          ),
          if (selectedDay case final day?)
            InputChip(
              label: Text(
                '${day.month}月${day.day}日',
                style: theme.textTheme.labelMedium,
              ),
              onDeleted: onClearDay,
              deleteIcon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
            )
          else
            Text(
              '含未安排时间的事项',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// 列表里的一条事项。
class _AgendaItemTile extends StatelessWidget {
  const _AgendaItemTile({
    required this.item,
    required this.onOpen,
    required this.onToggleCompleted,
    required this.onTogglePinned,
  });

  final AgendaItem item;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onTogglePinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lines = _details(context);
    return ListTile(
      leading: Checkbox(
        value: item.completed,
        onChanged: (value) {
          if (value != null) onToggleCompleted(value);
        },
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: item.completed ? TextDecoration.lineThrough : null,
          color: item.completed ? colors.onSurfaceVariant : colors.onSurface,
        ),
      ),
      subtitle: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (text, isNote) in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      text,
                      maxLines: isNote ? 2 : null,
                      overflow: isNote ? TextOverflow.ellipsis : null,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
      trailing: IconButton(
        tooltip: item.pinned ? '取消置顶' : '置顶',
        icon: Icon(
          item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
          size: 20,
          color: item.pinned ? colors.primary : colors.onSurfaceVariant,
        ),
        onPressed: onTogglePinned,
      ),
      onTap: onOpen,
    );
  }

  List<(String, bool)> _details(BuildContext context) {
    final lines = <String>[];
    final schedule = item.schedule?.moment;
    if (schedule != null) {
      lines.add('安排：${formatAgendaMoment(context, schedule)}');
    }
    final due = item.due?.moment;
    if (due != null) {
      lines.add('截止：${formatAgendaMoment(context, due)}');
    }
    final pending = item.reminders.where((reminder) => reminder.pending);
    if (pending.isNotEmpty) {
      final first = pending.first.moment;
      final text = first == null
          ? '${pending.length} 条提醒'
          : pending.length == 1
          ? '提醒：${formatAgendaMoment(context, first)}'
          : '提醒：${formatAgendaMoment(context, first)} 等 ${pending.length} 条';
      lines.add(text);
    }
    return [
      for (final line in lines) (line, false),
      if (item.notes?.trim() case final note? when note.isNotEmpty)
        (note, true),
    ];
  }
}
