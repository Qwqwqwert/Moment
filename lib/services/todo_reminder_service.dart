import 'dart:io';

import '../data/todo_repository.dart';
import '../models/todo.dart';
import 'android_todo_reminder_backend.dart';
import 'todo_reminder_backend.dart';
import 'windows_todo_reminder_backend.dart';

class TodoReminderService {
  TodoReminderService()
    : _backend = Platform.isWindows
          ? WindowsTodoReminderBackend()
          : AndroidTodoReminderBackend();

  final TodoReminderBackend _backend;

  Future<void> initialize() => _backend.initialize();

  void bindRepository(Object repository) => _backend.bindDeliveryRepository(
    repository is WindowsReminderDeliveryRepository ? repository : null,
  );

  Future<bool> requestPermission() => _backend.requestPermission();
  Future<bool> requestNotificationPermission() =>
      _backend.requestNotificationPermission();
  Future<void> syncReminders(Iterable<Todo> todos) =>
      _backend.syncReminders(todos);
  Future<void> resume(Iterable<Todo> todos) => _backend.resume(todos);
  Future<void> cancel(String todoId) => _backend.cancel(todoId);
  Future<bool> openNotificationSettings() =>
      _backend.openNotificationSettings();
  Future<bool> showTestReminder() => _backend.showTestReminder();
  Future<void> dispose() => _backend.dispose();
}
