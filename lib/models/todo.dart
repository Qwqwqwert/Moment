import 'note.dart';

enum TodoRepeat { none, daily, weekly, monthly, yearly }

enum TodoPriority { p0, p1, p2 }

class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.priority = TodoPriority.p1,
    this.reminderEnabled = false,
    this.repeat = TodoRepeat.none,
    this.repeatDayOfMonth,
    this.repeatMonth,
    this.isCompleted = false,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String description;
  final DateTime dueAt;
  final TodoPriority priority;
  final bool reminderEnabled;
  final TodoRepeat repeat;
  final int? repeatDayOfMonth;
  final int? repeatMonth;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Todo copyWith({
    String? title,
    String? description,
    DateTime? dueAt,
    TodoPriority? priority,
    bool? reminderEnabled,
    TodoRepeat? repeat,
    int? repeatDayOfMonth,
    int? repeatMonth,
    bool? isCompleted,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Todo(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    dueAt: dueAt ?? this.dueAt,
    priority: priority ?? this.priority,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    repeat: repeat ?? this.repeat,
    repeatDayOfMonth: repeatDayOfMonth ?? this.repeatDayOfMonth,
    repeatMonth: repeatMonth ?? this.repeatMonth,
    isCompleted: isCompleted ?? this.isCompleted,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Todo? nextOccurrence({DateTime? dueAtOverride}) {
    if (repeat == TodoRepeat.none) return null;
    final next =
        dueAtOverride ??
        switch (repeat) {
          TodoRepeat.daily => dueAt.add(const Duration(days: 1)),
          TodoRepeat.weekly => dueAt.add(const Duration(days: 7)),
          TodoRepeat.monthly => _nextMonthly(dueAt),
          TodoRepeat.yearly => _nextYearly(dueAt),
          TodoRepeat.none => dueAt,
        };
    final now = DateTime.now();
    return Todo(
      id: newId(),
      title: title,
      description: description,
      dueAt: next,
      priority: priority,
      reminderEnabled: reminderEnabled,
      repeat: repeat,
      repeatDayOfMonth:
          repeat == TodoRepeat.monthly || repeat == TodoRepeat.yearly
          ? repeatDayOfMonth ?? dueAt.day
          : null,
      repeatMonth: repeat == TodoRepeat.yearly
          ? repeatMonth ?? dueAt.month
          : null,
      createdAt: now,
      updatedAt: now,
    );
  }

  static DateTime _nextMonthly(DateTime source) {
    for (var offset = 1; offset <= 24; offset++) {
      final first = DateTime(
        source.year,
        source.month + offset,
        1,
        source.hour,
        source.minute,
      );
      final lastDay = DateTime(first.year, first.month + 1, 0).day;
      if (source.day <= lastDay) {
        return DateTime(
          first.year,
          first.month,
          source.day,
          source.hour,
          source.minute,
        );
      }
    }
    return DateTime(
      source.year,
      source.month + 1,
      1,
      source.hour,
      source.minute,
    );
  }

  static DateTime _nextYearly(DateTime source) {
    final year = source.year + 1;
    final lastDay = DateTime(year, source.month + 1, 0).day;
    return DateTime(
      year,
      source.month,
      source.day.clamp(1, lastDay).toInt(),
      source.hour,
      source.minute,
    );
  }
}
