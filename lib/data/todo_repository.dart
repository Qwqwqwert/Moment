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
