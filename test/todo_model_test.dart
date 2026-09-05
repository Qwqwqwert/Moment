import 'package:flutter_test/flutter_test.dart';
import 'package:moment/models/todo.dart';

void main() {
  Todo todo(DateTime dueAt, TodoRepeat repeat) => Todo(
    id: 'todo',
    title: '测试',
    dueAt: dueAt,
    repeat: repeat,
    createdAt: dueAt,
    updatedAt: dueAt,
  );

  test('daily and weekly todos calculate the next occurrence', () {
    final source = DateTime(2026, 8, 20, 18, 30);
    expect(
      todo(source, TodoRepeat.daily).nextOccurrence()!.dueAt,
      DateTime(2026, 8, 21, 18, 30),
    );
    expect(
      todo(source, TodoRepeat.weekly).nextOccurrence()!.dueAt,
      DateTime(2026, 8, 27, 18, 30),
    );
  });

  test('monthly recurrence skips months without its original day', () {
    final next = todo(
      DateTime(2026, 1, 31, 9),
      TodoRepeat.monthly,
    ).nextOccurrence();
    expect(next!.dueAt, DateTime(2026, 3, 31, 9));
  });

  test('yearly leap-day recurrence uses the last valid February day', () {
    final next = todo(
      DateTime(2024, 2, 29, 9),
      TodoRepeat.yearly,
    ).nextOccurrence();
    expect(next!.dueAt, DateTime(2025, 2, 28, 9));
  });

  test('an adjusted monthly occurrence preserves its original day', () {
    final source = Todo(
      id: 'monthly',
      title: '月度待办',
      dueAt: DateTime(2026, 1, 31, 9),
      repeat: TodoRepeat.monthly,
      repeatDayOfMonth: 31,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final next = source.nextOccurrence(
      dueAtOverride: DateTime(2026, 2, 28, 9),
    );
    expect(next!.dueAt, DateTime(2026, 2, 28, 9));
    expect(next.repeatDayOfMonth, 31);
  });

  test('an adjusted leap-day occurrence preserves February 29', () {
    final source = Todo(
      id: 'yearly',
      title: '周年待办',
      dueAt: DateTime(2024, 2, 29, 9),
      repeat: TodoRepeat.yearly,
      repeatDayOfMonth: 29,
      repeatMonth: 2,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final next = source.nextOccurrence(
      dueAtOverride: DateTime(2025, 2, 28, 9),
    );
    expect(next!.dueAt, DateTime(2025, 2, 28, 9));
    expect(next.repeatDayOfMonth, 29);
    expect(next.repeatMonth, 2);
  });
}
