import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../models/todo.dart';
import '../state/app_controller.dart';
import 'note_library_screens.dart';

class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

enum _TodoTimeGroup { overdue, withinSevenDays, afterSevenDays }

const _todoCompletionAnimationDuration = Duration(milliseconds: 420);

int _compareTodos(Todo a, Todo b) {
  final dueAtComparison = a.dueAt.compareTo(b.dueAt);
  if (dueAtComparison != 0) return dueAtComparison;
  final priorityComparison = a.priority.index.compareTo(b.priority.index);
  if (priorityComparison != 0) return priorityComparison;
  return a.createdAt.compareTo(b.createdAt);
}

class _TodosScreenState extends State<TodosScreen> {
  late DateTime _selected;
  late DateTime _visibleMonth;
  bool _overdueExpanded = false;
  bool _withinSevenDaysExpanded = true;
  bool _afterSevenDaysExpanded = false;
  final _completingTodoIds = <String>{};
  final _todoKeys = <String, GlobalKey>{};
  DateTime? _flashDate;
  int _flashGeneration = 0;
  int _revealRequest = 0;

  @override
  void initState() {
    super.initState();
    _selected = DateUtils.dateOnly(DateTime.now());
    _visibleMonth = DateTime(_selected.year, _selected.month);
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) _selectDate(value);
  }

  void _changeMonth(int offset) => setState(() {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
  });

  void _selectDate(DateTime value) {
    final selected = DateUtils.dateOnly(value);
    setState(() {
      _selected = selected;
      _flashDate = null;
      if (value.year != _visibleMonth.year ||
          value.month != _visibleMonth.month) {
        _visibleMonth = DateTime(value.year, value.month);
      }
      _focusGroupFor(value);
    });
    _revealTodosFor(selected, ++_revealRequest);
  }

  Future<void> _revealTodosFor(DateTime date, int request) async {
    final matching =
        AppScope.read(context).todos
            .where(
              (todo) =>
                  !todo.isCompleted && DateUtils.isSameDay(todo.dueAt, date),
            )
            .toList()
          ..sort(_compareTodos);
    if (matching.isEmpty) return;
    final targetId = matching.first.id;
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted || request != _revealRequest) return;
    final targetContext = _todoKeys[targetId]?.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeInOutCubic,
      alignment: .12,
    );
    if (!mounted || request != _revealRequest) return;
    setState(() {
      _flashDate = date;
      _flashGeneration++;
    });
  }

  _TodoTimeGroup _groupFor(DateTime value) {
    final today = DateUtils.dateOnly(DateTime.now());
    final date = DateUtils.dateOnly(value);
    if (date.isBefore(today)) return _TodoTimeGroup.overdue;
    final lastDay = today.add(const Duration(days: 7));
    return date.isAfter(lastDay)
        ? _TodoTimeGroup.afterSevenDays
        : _TodoTimeGroup.withinSevenDays;
  }

  void _focusGroupFor(DateTime value) {
    final group = _groupFor(value);
    _overdueExpanded = group == _TodoTimeGroup.overdue;
    _withinSevenDaysExpanded = group == _TodoTimeGroup.withinSevenDays;
    _afterSevenDaysExpanded = group == _TodoTimeGroup.afterSevenDays;
  }

  Future<void> _openEditor([Todo? todo]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TodoEditorScreen(todoId: todo?.id, initialDate: _selected),
      ),
    );
  }

  Future<void> _openDestination(String destination) async {
    final page = switch (destination) {
      'completed' => const CompletedTodosScreen(),
      'trash' => const TodoTrashScreen(),
      _ => const SettingsScreen(),
    };
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _completeTodo(AppController app, Todo todo) async {
    if (_completingTodoIds.contains(todo.id)) return;
    final choice = _repeatCompletionChoice(todo);
    DateTime? nextDueAt;
    if (choice != null) {
      nextDueAt = await showDialog<DateTime>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.event_repeat_rounded),
          title: Text(choice.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(choice.message),
              const SizedBox(height: 16),
              _RepeatDateChoice(
                label: choice.firstLabel,
                date: choice.firstDate,
                onTap: () => Navigator.pop(dialogContext, choice.firstDate),
              ),
              const SizedBox(height: 8),
              _RepeatDateChoice(
                label: choice.secondLabel,
                date: choice.secondDate,
                onTap: () => Navigator.pop(dialogContext, choice.secondDate),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (nextDueAt == null || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _completingTodoIds.add(todo.id));
    await Future<void>.delayed(_todoCompletionAnimationDuration);
    try {
      await app.completeTodo(todo.id, true, nextDueAt: nextDueAt);
    } catch (_) {
      if (mounted) setState(() => _completingTodoIds.remove(todo.id));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final todos = app.todos.where((todo) => !todo.isCompleted).toList()
      ..sort(_compareTodos);
    final overdue = todos
        .where((todo) => _groupFor(todo.dueAt) == _TodoTimeGroup.overdue)
        .toList();
    final withinSevenDays = todos
        .where(
          (todo) => _groupFor(todo.dueAt) == _TodoTimeGroup.withinSevenDays,
        )
        .toList();
    final afterSevenDays = todos
        .where((todo) => _groupFor(todo.dueAt) == _TodoTimeGroup.afterSevenDays)
        .toList();
    final activeTodoIds = todos.map((todo) => todo.id).toSet();
    _todoKeys.removeWhere((id, _) => !activeTodoIds.contains(id));
    final finishedAnimations = _completingTodoIds
        .where((id) => !activeTodoIds.contains(id))
        .toSet();
    if (finishedAnimations.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _completingTodoIds.removeAll(finishedAnimations));
      });
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('待办'),
            const SizedBox(height: 2),
            Text(
              '${todos.length} 项任务',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          _TodoHomeMenu(onNavigate: _openDestination),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _TodoCalendar(
            selected: _selected,
            visibleMonth: _visibleMonth,
            todos: app.todos,
            onSelected: _selectDate,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
            onPickMonth: _pickDate,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
              children: [
                _TodoGroupSection(
                  title: '已逾期',
                  todos: overdue,
                  expanded: _overdueExpanded,
                  countColor: theme.colorScheme.error,
                  completingTodoIds: _completingTodoIds,
                  flashDate: _flashDate,
                  flashGeneration: _flashGeneration,
                  todoKeys: _todoKeys,
                  onToggle: () =>
                      setState(() => _overdueExpanded = !_overdueExpanded),
                  onOpen: _openEditor,
                  onComplete: (todo) => _completeTodo(app, todo),
                ),
                const SizedBox(height: 10),
                _TodoGroupSection(
                  title: '7天内',
                  todos: withinSevenDays,
                  expanded: _withinSevenDaysExpanded,
                  completingTodoIds: _completingTodoIds,
                  flashDate: _flashDate,
                  flashGeneration: _flashGeneration,
                  todoKeys: _todoKeys,
                  onToggle: () => setState(
                    () => _withinSevenDaysExpanded = !_withinSevenDaysExpanded,
                  ),
                  onOpen: _openEditor,
                  onComplete: (todo) => _completeTodo(app, todo),
                ),
                const SizedBox(height: 10),
                _TodoGroupSection(
                  title: '7天之后',
                  todos: afterSevenDays,
                  expanded: _afterSevenDaysExpanded,
                  completingTodoIds: _completingTodoIds,
                  flashDate: _flashDate,
                  flashGeneration: _flashGeneration,
                  todoKeys: _todoKeys,
                  onToggle: () => setState(
                    () => _afterSevenDaysExpanded = !_afterSevenDaysExpanded,
                  ),
                  onOpen: _openEditor,
                  onComplete: (todo) => _completeTodo(app, todo),
                ),
                if (todos.isEmpty) ...[
                  const SizedBox(height: 28),
                  _TodoEmpty(onAdd: _openEditor),
                ],
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'todos-primary-action',
        onPressed: _openEditor,
        tooltip: '新建待办',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _TodoHomeMenu extends StatelessWidget {
  const _TodoHomeMenu({required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(-192, 52),
      style: MenuStyle(
        alignment: AlignmentDirectional.topEnd,
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(
          colors.shadow.withValues(alpha: .18),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(9)),
        minimumSize: const WidgetStatePropertyAll(Size(192, 0)),
        maximumSize: const WidgetStatePropertyAll(Size(192, double.infinity)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 174,
          child: _TodoMenuItem(
            icon: Icons.history_rounded,
            label: '已完成',
            onPressed: () => onNavigate('completed'),
          ),
        ),
        _TodoMenuItem(
          icon: Icons.delete_outline_rounded,
          label: '回收站',
          onPressed: () => onNavigate('trash'),
        ),
        const Divider(height: 12),
        _TodoMenuItem(
          icon: Icons.settings_outlined,
          label: '设置',
          onPressed: () => onNavigate('settings'),
        ),
      ],
      builder: (context, controller, child) => IconButton.filledTonal(
        tooltip: '管理与设置',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune_rounded, size: 21),
      ),
    );
  }
}

class _TodoMenuItem extends StatelessWidget {
  const _TodoMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MenuItemButton(
    onPressed: onPressed,
    leadingIcon: Icon(icon, size: 20),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    ),
  );
}

class _RepeatCompletionChoiceData {
  const _RepeatCompletionChoiceData({
    required this.title,
    required this.message,
    required this.firstLabel,
    required this.firstDate,
    required this.secondLabel,
    required this.secondDate,
  });

  final String title;
  final String message;
  final String firstLabel;
  final DateTime firstDate;
  final String secondLabel;
  final DateTime secondDate;
}

_RepeatCompletionChoiceData? _repeatCompletionChoice(Todo todo) {
  if (todo.repeat == TodoRepeat.monthly) {
    return _monthlyCompletionChoice(todo);
  }
  if (todo.repeat == TodoRepeat.yearly) {
    return _yearlyCompletionChoice(todo);
  }
  return null;
}

_RepeatCompletionChoiceData? _monthlyCompletionChoice(Todo todo) {
  final current = todo.dueAt;
  final originalDay = todo.repeatDayOfMonth ?? current.day;
  final nextMonth = DateTime(current.year, current.month + 1);
  final nextMonthDays = _daysInMonth(nextMonth.year, nextMonth.month);

  if (originalDay > nextMonthDays && current.day == originalDay) {
    final adjusted = _withTodoTime(
      current,
      nextMonth.year,
      nextMonth.month,
      nextMonthDays,
    );
    late DateTime nextValid;
    for (var offset = 2; offset <= 24; offset++) {
      final candidate = DateTime(current.year, current.month + offset);
      if (originalDay <= _daysInMonth(candidate.year, candidate.month)) {
        nextValid = _withTodoTime(
          current,
          candidate.year,
          candidate.month,
          originalDay,
        );
        break;
      }
    }
    return _RepeatCompletionChoiceData(
      title: '调整重复日期',
      message: '下个月没有 $originalDay 日，请选择下一条待办的日期。',
      firstLabel: '改到下个月的最后一天',
      firstDate: adjusted,
      secondLabel: '保留 $originalDay 日，跳到下一个有效月份',
      secondDate: nextValid,
    );
  }

  if (current.day != originalDay && originalDay <= nextMonthDays) {
    final continued = _withTodoTime(
      current,
      nextMonth.year,
      nextMonth.month,
      current.day.clamp(1, nextMonthDays).toInt(),
    );
    final restored = _withTodoTime(
      current,
      nextMonth.year,
      nextMonth.month,
      originalDay,
    );
    return _RepeatCompletionChoiceData(
      title: '恢复原始重复日期',
      message: '下个月已有原始设定的 $originalDay 日，是否恢复？',
      firstLabel: '继续使用调整后的日期',
      firstDate: continued,
      secondLabel: '恢复到原始日期',
      secondDate: restored,
    );
  }
  return null;
}

_RepeatCompletionChoiceData? _yearlyCompletionChoice(Todo todo) {
  final current = todo.dueAt;
  final originalMonth = todo.repeatMonth ?? current.month;
  final originalDay = todo.repeatDayOfMonth ?? current.day;
  if (originalMonth != DateTime.february || originalDay != 29) return null;

  final nextYear = current.year + 1;
  final nextYearHasLeapDay = _daysInMonth(nextYear, DateTime.february) == 29;
  final currentlyOnOriginalDate =
      current.month == DateTime.february && current.day == 29;

  if (currentlyOnOriginalDate && !nextYearHasLeapDay) {
    final nextFebruary28 = _withTodoTime(
      current,
      nextYear,
      DateTime.february,
      28,
    );
    var leapYear = nextYear + 1;
    while (_daysInMonth(leapYear, DateTime.february) != 29) {
      leapYear++;
    }
    final nextFebruary29 = _withTodoTime(
      current,
      leapYear,
      DateTime.february,
      29,
    );
    return _RepeatCompletionChoiceData(
      title: '选择下一轮日期',
      message: '来年没有 2 月 29 日，请选择下一条待办的日期。',
      firstLabel: '改到来年 2 月 28 日',
      firstDate: nextFebruary28,
      secondLabel: '保留 2 月 29 日，跳到下一个闰年',
      secondDate: nextFebruary29,
    );
  }

  if (!currentlyOnOriginalDate && nextYearHasLeapDay) {
    final continued = _withTodoTime(current, nextYear, DateTime.february, 28);
    final restored = _withTodoTime(current, nextYear, DateTime.february, 29);
    return _RepeatCompletionChoiceData(
      title: '恢复闰日重复',
      message: '$nextYear年已有 2 月 29 日，是否恢复原始日期？',
      firstLabel: '继续使用 2 月 28 日',
      firstDate: continued,
      secondLabel: '恢复到 2 月 29 日',
      secondDate: restored,
    );
  }
  return null;
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _withTodoTime(DateTime source, int year, int month, int day) =>
    DateTime(
      year,
      month,
      day,
      source.hour,
      source.minute,
      source.second,
      source.millisecond,
      source.microsecond,
    );

class _RepeatDateChoice extends StatelessWidget {
  const _RepeatDateChoice({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 3),
                  Text(
                    _fullDate(date),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}

class _TodoCalendar extends StatelessWidget {
  const _TodoCalendar({
    required this.selected,
    required this.visibleMonth,
    required this.todos,
    required this.onSelected,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onPickMonth,
  });

  final DateTime selected;
  final DateTime visibleMonth;
  final List<Todo> todos;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onPickMonth;

  List<DateTime> get _days {
    final first = DateTime(visibleMonth.year, visibleMonth.month);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }

  Iterable<Todo> _todosOn(DateTime date) => todos.where(
    (todo) => !todo.isCompleted && DateUtils.isSameDay(todo.dueAt, date),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final days = _days;
    const markerColors = _TodoMarkerColors(
      Color.fromARGB(255, 74, 158, 51),
      Color.fromARGB(255, 255, 85, 0),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: onPreviousMonth,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onPickMonth,
                  child: SizedBox(
                    height: 38,
                    child: Center(
                      child: Text(
                        '${visibleMonth.year}年${visibleMonth.month}月',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: onNextMonth,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: const ['日', '一', '二', '三', '四', '五', '六']
                .map(
                  (weekday) => Expanded(
                    child: Text(
                      weekday,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 36,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              final date = days[index];
              final dayTodos = _todosOn(date).toList();
              final hasNormal = dayTodos.any(
                (todo) => todo.repeat == TodoRepeat.none,
              );
              final hasRepeating = dayTodos.any(
                (todo) => todo.repeat != TodoRepeat.none,
              );
              final isSelected = DateUtils.isSameDay(date, selected);
              final isToday = DateUtils.isSameDay(date, today);
              final isCurrentMonth =
                  date.year == visibleMonth.year &&
                  date.month == visibleMonth.month;
              final hasTodo = hasNormal || hasRepeating;

              return Opacity(
                opacity: isCurrentMonth ? 1 : .42,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(date),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          color: hasTodo
                              ? colors.primaryContainer.withValues(alpha: .55)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(color: colors.primary)
                              : null,
                        ),
                      ),
                      AnimatedScale(
                        scale: isSelected ? 1 : .72,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: AnimatedOpacity(
                          opacity: isSelected ? 1 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            style:
                                (theme.textTheme.bodyMedium ??
                                        const TextStyle())
                                    .copyWith(
                                      color: isSelected
                                          ? colors.onPrimary
                                          : colors.onSurface,
                                      fontWeight: isSelected || hasTodo
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                            child: Text('${date.day}'),
                          ),
                        ),
                      ),
                      if (hasTodo)
                        Positioned(
                          bottom: 3,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasNormal)
                                  _CalendarDot(color: markerColors.normal),
                                if (hasNormal && hasRepeating)
                                  const SizedBox(width: 3),
                                if (hasRepeating)
                                  _CalendarDot(color: markerColors.repeating),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CalendarLegend(color: markerColors.normal, label: '普通待办'),
              const SizedBox(width: 16),
              _CalendarLegend(color: markerColors.repeating, label: '重复待办'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarDot extends StatelessWidget {
  const _CalendarDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const SizedBox.square(dimension: 5),
  );
}

class _TodoMarkerColors {
  const _TodoMarkerColors(this.normal, this.repeating);

  final Color normal;
  final Color repeating;
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CalendarDot(color: color),
      const SizedBox(width: 5),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );
}

class _TodoGroupSection extends StatelessWidget {
  const _TodoGroupSection({
    required this.title,
    required this.todos,
    required this.expanded,
    required this.completingTodoIds,
    this.countColor,
    required this.flashDate,
    required this.flashGeneration,
    required this.todoKeys,
    required this.onToggle,
    required this.onOpen,
    required this.onComplete,
  });

  final String title;
  final List<Todo> todos;
  final bool expanded;
  final Set<String> completingTodoIds;
  final Color? countColor;
  final DateTime? flashDate;
  final int flashGeneration;
  final Map<String, GlobalKey> todoKeys;
  final VoidCallback onToggle;
  final ValueChanged<Todo> onOpen;
  final ValueChanged<Todo> onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: expanded ? .25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.chevron_right_rounded, size: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${todos.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: countColor ?? colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded && todos.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: todos
                        .map(
                          (todo) => _TodoCard(
                            key: todoKeys.putIfAbsent(todo.id, GlobalKey.new),
                            todo: todo,
                            completing: completingTodoIds.contains(todo.id),
                            flashToken:
                                DateUtils.isSameDay(todo.dueAt, flashDate)
                                ? flashGeneration
                                : 0,
                            onTap: () => onOpen(todo),
                            onComplete: () => onComplete(todo),
                          ),
                        )
                        .toList(),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _TodoEmpty extends StatelessWidget {
  const _TodoEmpty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.task_alt_rounded,
          size: 52,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .65),
        ),
        const SizedBox(height: 10),
        Text('暂无待办', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        TextButton(onPressed: onAdd, child: const Text('创建一项待办')),
      ],
    ),
  );
}

class _TodoCard extends StatefulWidget {
  const _TodoCard({
    super.key,
    required this.todo,
    required this.onTap,
    required this.onComplete,
    this.completed = false,
    this.completing = false,
    this.flashToken = 0,
  });
  final Todo todo;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final bool completed;
  final bool completing;
  final int flashToken;

  @override
  State<_TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<_TodoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;
  late final Animation<double> _flash;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _flash =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
        );
  }

  @override
  void didUpdateWidget(covariant _TodoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashToken > 0 && widget.flashToken != oldWidget.flashToken) {
      _flashController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue =
        !widget.completed && widget.todo.dueAt.isBefore(DateTime.now());
    final card = AnimatedBuilder(
      animation: _flash,
      builder: (context, child) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        color: Color.lerp(
          theme.cardTheme.color ?? theme.colorScheme.surface,
          theme.colorScheme.primaryContainer,
          _flash.value * .82,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: widget.completed ? '恢复待办' : '完成待办',
                  onPressed: widget.onComplete,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      widget.completed || widget.completing
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(widget.completed || widget.completing),
                      color: widget.completed || widget.completing
                          ? Colors.green
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.todo.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: widget.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (widget.todo.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.todo.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _TodoPriorityBadge(priority: widget.todo.priority),
                          _TodoMeta(
                            icon: Icons.schedule_rounded,
                            label: _todoDateTimeLabel(widget.todo.dueAt),
                            alert: overdue,
                          ),
                          if (widget.todo.repeat != TodoRepeat.none)
                            _TodoMeta(
                              icon: Icons.repeat_rounded,
                              label: _repeatLabel(widget.todo.repeat),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      duration: _todoCompletionAnimationDuration,
      curve: Curves.easeInOutCubic,
      tween: Tween<double>(begin: 1, end: widget.completing ? 0 : 1),
      builder: (context, value, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: value,
          child: Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(20 * (1 - value), 0),
              child: child,
            ),
          ),
        ),
      ),
      child: IgnorePointer(ignoring: widget.completing, child: card),
    );
  }
}

class _TodoMeta extends StatelessWidget {
  const _TodoMeta({
    required this.icon,
    required this.label,
    this.alert = false,
  });
  final IconData icon;
  final String label;
  final bool alert;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = alert ? colors.error : colors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}

class _TodoPriorityBadge extends StatelessWidget {
  const _TodoPriorityBadge({required this.priority});

  final TodoPriority priority;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (priority) {
      TodoPriority.p0 => (colors.errorContainer, colors.onErrorContainer),
      TodoPriority.p1 => (colors.primaryContainer, colors.onPrimaryContainer),
      TodoPriority.p2 => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority.name.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class TodoEditorScreen extends StatefulWidget {
  const TodoEditorScreen({super.key, this.todoId, required this.initialDate});
  final String? todoId;
  final DateTime initialDate;

  @override
  State<TodoEditorScreen> createState() => _TodoEditorScreenState();
}

class _TodoEditorScreenState extends State<TodoEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late DateTime _dueAt;
  late TodoPriority _priority;
  late TodoRepeat _repeat;
  Todo? _source;
  bool _repeatScheduleChanged = false;

  String? get _repeatHint => switch (_repeat) {
    TodoRepeat.weekly => '将于每${_weekdayLabel(_dueAt.weekday)}重复',
    TodoRepeat.monthly => '将于每月${_dueAt.day}日重复',
    TodoRepeat.yearly => '将于每年${_dueAt.month}月${_dueAt.day}日重复',
    TodoRepeat.none => null,
    TodoRepeat.daily => null,
  };

  @override
  void initState() {
    super.initState();
    _source = widget.todoId == null
        ? null
        : AppScope.read(context).findTodo(widget.todoId!);
    final initial = widget.initialDate;
    _dueAt =
        _source?.dueAt ??
        DateTime(initial.year, initial.month, initial.day, 10);
    _priority = _source?.priority ?? TodoPriority.p1;
    _repeat = _source?.repeat ?? TodoRepeat.none;
    _title = TextEditingController(text: _source?.title ?? '');
    _description = TextEditingController(text: _source?.description ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() {
        final updated = DateTime(
          date.year,
          date.month,
          date.day,
          _dueAt.hour,
          _dueAt.minute,
        );
        if (!DateUtils.isSameDay(updated, _dueAt)) {
          _repeatScheduleChanged = true;
        }
        _dueAt = updated;
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (time != null) {
      setState(
        () => _dueAt = DateTime(
          _dueAt.year,
          _dueAt.month,
          _dueAt.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入待办标题')));
      return;
    }
    final now = DateTime.now();
    await AppScope.read(context).saveTodo(
      Todo(
        id: _source?.id ?? newId(),
        title: title,
        description: _description.text.trim(),
        dueAt: _dueAt,
        priority: _priority,
        repeat: _repeat,
        repeatDayOfMonth:
            _repeat == TodoRepeat.monthly || _repeat == TodoRepeat.yearly
            ? (_source != null &&
                      !_repeatScheduleChanged &&
                      _source!.repeat == _repeat
                  ? _source!.repeatDayOfMonth ?? _source!.dueAt.day
                  : _dueAt.day)
            : null,
        repeatMonth: _repeat == TodoRepeat.yearly
            ? (_source != null &&
                      !_repeatScheduleChanged &&
                      _source!.repeat == _repeat
                  ? _source!.repeatMonth ?? _source!.dueAt.month
                  : _dueAt.month)
            : null,
        isCompleted: _source?.isCompleted ?? false,
        createdAt: _source?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (_source == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除待办？'),
        content: const Text('待办将移入回收站。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await AppScope.read(context).trashTodos([_source!.id]);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_source == null ? '新建待办' : '编辑待办'),
      actions: [
        if (_source != null)
          IconButton(
            tooltip: '删除',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        TextButton(onPressed: _save, child: const Text('保存')),
        const SizedBox(width: 8),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: _title,
          autofocus: _source == null,
          maxLength: 20,
          inputFormatters: [LengthLimitingTextInputFormatter(20)],
          decoration: const InputDecoration(
            labelText: '标题',
            hintText: '要完成什么？',
            prefixIcon: Icon(Icons.task_alt_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _description,
          maxLength: 100,
          maxLines: 4,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          decoration: const InputDecoration(
            labelText: '备注',
            hintText: '补充一些细节（可选）',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        Text('截止时间', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${_dueAt.year}-${_dueAt.month.toString().padLeft(2, '0')}-${_dueAt.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(_time(_dueAt)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('优先级', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: TodoPriority.values
              .map(
                (value) => ChoiceChip(
                  showCheckmark: false,
                  label: Text(value.name.toUpperCase()),
                  selected: _priority == value,
                  onSelected: (_) => setState(() => _priority = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        Text('重复', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TodoRepeat.values
              .map(
                (value) => ChoiceChip(
                  showCheckmark: false,
                  label: Text(_repeatLabel(value)),
                  selected: _repeat == value,
                  onSelected: (_) => setState(() {
                    if (_repeat != value) _repeatScheduleChanged = true;
                    _repeat = value;
                  }),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _repeatHint == null
              ? const SizedBox.shrink(key: ValueKey('repeat-hint-empty'))
              : Container(
                  key: ValueKey(_repeat),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_repeat_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _repeatHint!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );
}

class CompletedTodosScreen extends StatelessWidget {
  const CompletedTodosScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final todos = app.todos.where((todo) => todo.isCompleted).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('已完成')),
      body: todos.isEmpty
          ? const Center(child: Text('暂无已完成待办'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: todos.length,
              itemBuilder: (context, index) => _TodoCard(
                todo: todos[index],
                completed: true,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TodoEditorScreen(
                      todoId: todos[index].id,
                      initialDate: todos[index].dueAt,
                    ),
                  ),
                ),
                onComplete: () => app.completeTodo(todos[index].id, false),
              ),
            ),
    );
  }
}

class TodoTrashScreen extends StatelessWidget {
  const TodoTrashScreen({super.key});

  Future<void> _delete(BuildContext context, Todo todo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除待办？'),
        content: Text('“${todo.title}”删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AppScope.read(context).deleteTodosForever([todo.id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final todos = app.trashedTodos;
    return Scaffold(
      appBar: AppBar(title: const Text('待办回收站')),
      body: todos.isEmpty
          ? const Center(child: Text('回收站暂无待办'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: todos.length,
              itemBuilder: (context, index) {
                final todo = todos[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.task_alt_rounded),
                    title: Text(todo.title),
                    subtitle: Text(
                      '${todo.dueAt.year}-${todo.dueAt.month.toString().padLeft(2, '0')}-${todo.dueAt.day.toString().padLeft(2, '0')} ${_time(todo.dueAt)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) => value == 'restore'
                          ? app.restoreTodos([todo.id])
                          : _delete(context, todo),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'restore', child: Text('恢复')),
                        PopupMenuItem(value: 'delete', child: Text('永久删除')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _time(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String _todoDateTimeLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${_time(date)}';
String _fullDate(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日 ${_time(date)}';
String _weekdayLabel(int weekday) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];
String _repeatLabel(TodoRepeat value) => switch (value) {
  TodoRepeat.none => '不重复',
  TodoRepeat.daily => '每天',
  TodoRepeat.weekly => '每周',
  TodoRepeat.monthly => '每月',
  TodoRepeat.yearly => '每年',
};
