import '../data/todo_repository.dart';
import '../models/todo.dart';

abstract interface class TodoReminderBackend {
  Future<void> initialize();
  void bindDeliveryRepository(WindowsReminderDeliveryRepository? repository);
  Future<bool> requestPermission();
  Future<bool> requestNotificationPermission();
  Future<void> syncReminders(Iterable<Todo> todos);
  Future<void> resume(Iterable<Todo> todos);
  Future<void> cancel(String todoId);
  Future<bool> openNotificationSettings();
  Future<bool> showTestReminder();
  Future<void> dispose();
}
