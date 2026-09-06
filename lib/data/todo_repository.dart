import '../models/todo.dart';

abstract interface class TodoRepository {
  Future<List<Todo>> getTodos({bool deleted = false, bool? completed});
  Future<Todo?> getTodo(String id, {bool includeDeleted = false});
  Future<void> saveTodo(Todo todo);
  Future<void> setTodoCompleted(
    String id,
    bool completed, {
    DateTime? nextDueAt,
  });
  Future<void> moveTodosToTrash(Iterable<String> ids);
  Future<void> restoreTodos(Iterable<String> ids);
  Future<void> permanentlyDeleteTodos(Iterable<String> ids);
}

/// Persistent de-duplication for runtime desktop reminders.
abstract interface class RuntimeReminderDeliveryRepository {
  Future<bool> wasReminderDelivered(String todoId, DateTime dueAt);
  Future<void> markReminderDelivered(String todoId, DateTime dueAt);
  Future<void> pruneReminderDeliveries(DateTime before);

  @Deprecated('Use wasReminderDelivered instead')
  Future<bool> wasWindowsReminderDelivered(String todoId, DateTime dueAt) =>
      wasReminderDelivered(todoId, dueAt);

  @Deprecated('Use markReminderDelivered instead')
  Future<void> markWindowsReminderDelivered(String todoId, DateTime dueAt) =>
      markReminderDelivered(todoId, dueAt);

  @Deprecated('Use pruneReminderDeliveries instead')
  Future<void> pruneWindowsReminderDeliveries(DateTime before) =>
      pruneReminderDeliveries(before);
}

@Deprecated('Use RuntimeReminderDeliveryRepository instead')
typedef WindowsReminderDeliveryRepository = RuntimeReminderDeliveryRepository;
