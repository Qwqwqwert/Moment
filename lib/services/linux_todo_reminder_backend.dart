import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/todo_repository.dart';
import '../models/todo.dart';
import 'android_todo_reminder_backend.dart' show notificationId;
import 'todo_reminder_backend.dart';

/// Runtime-only reminder backend for Ubuntu/Linux.
///
/// Linux desktop notification servers do not expose a portable scheduling API,
/// so reminders are held in memory while Moment is running (including when
/// its window is minimized).
class LinuxTodoReminderBackend implements TodoReminderBackend {
  static const _init = LinuxInitializationSettings(
    defaultActionName: '打开 Moment',
  );

  final _notifications = FlutterLocalNotificationsPlugin();
  final Map<String, Timer> _timers = {};
  RuntimeReminderDeliveryRepository? _deliveries;
  LinuxServerCapabilities? _capabilities;
  bool _initialized = false;
  int _generation = 0;

  LinuxFlutterLocalNotificationsPlugin? get _linux => _notifications
      .resolvePlatformSpecificImplementation<
        LinuxFlutterLocalNotificationsPlugin
      >();

  NotificationDetails get _details => NotificationDetails(
    linux: LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.critical,
      sound: _capabilities?.sound == true ? ThemeLinuxSound('message') : null,
      timeout: LinuxNotificationTimeout.fromDuration(
        const Duration(seconds: 10),
      ),
    ),
  );

  @override
  Future<void> initialize() async {
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(linux: _init),
      );
      _capabilities = await _linux?.getCapabilities();
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  @override
  void bindDeliveryRepository(RuntimeReminderDeliveryRepository? repository) {
    _deliveries = repository;
  }

  @override
  Future<bool> requestPermission() async => _initialized;

  @override
  Future<bool> requestNotificationPermission() async => _initialized;

  @override
  Future<void> syncReminders(Iterable<Todo> todos) async {
    final generation = ++_generation;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (!_initialized) return;

    final now = DateTime.now();
    await _deliveries?.pruneReminderDeliveries(
      now.subtract(const Duration(days: 32)),
    );
    for (final todo in todos) {
      if (!todo.reminderEnabled || todo.isCompleted || todo.isDeleted) {
        continue;
      }
      final delay = todo.dueAt.difference(now);
      if (delay <= Duration.zero) {
        if (todo.dueAt.isBefore(now.subtract(const Duration(hours: 24)))) {
          continue;
        }
        await _deliver(todo, generation);
      } else {
        _timers[todo.id] = Timer(delay, () {
          _timers.remove(todo.id);
          unawaited(_deliver(todo, generation));
        });
      }
    }
  }

  Future<void> _deliver(Todo todo, int generation) async {
    if (!_initialized || generation != _generation) return;
    if (await _deliveries?.wasReminderDelivered(todo.id, todo.dueAt) == true) {
      return;
    }
    try {
      await _notifications.show(
        id: notificationId(todo.id),
        title: todo.title,
        body: todo.description.isEmpty ? '待办时间到了' : todo.description,
        notificationDetails: _details,
        payload: 'todo:${todo.id}',
      );
      await _deliveries?.markReminderDelivered(todo.id, todo.dueAt);
    } catch (_) {}
  }

  @override
  Future<void> resume(Iterable<Todo> todos) => syncReminders(todos);

  @override
  Future<void> cancel(String todoId) async {
    _timers.remove(todoId)?.cancel();
    try {
      await _notifications.cancel(id: notificationId(todoId));
    } catch (_) {}
  }

  @override
  Future<bool> openNotificationSettings() async {
    try {
      await Process.start('gnome-control-center', [
        'notifications',
      ], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> showTestReminder() async {
    if (!_initialized) return false;
    try {
      await _notifications.show(
        id: 2147483000,
        title: 'Moment 待办提醒测试',
        body: 'Linux 通知可以正常发送。退出 Moment 后不会提醒。',
        notificationDetails: _details,
        payload: 'todo:test',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    _generation++;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
