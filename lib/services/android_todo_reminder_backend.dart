import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/todo_repository.dart';
import '../models/todo.dart';
import 'todo_reminder_backend.dart';

class AndroidTodoReminderBackend implements TodoReminderBackend {
  static const _legacyChannelIds = ['todo_reminders'];
  static const _channel = AndroidNotificationChannel(
    'todo_reminder_alerts_v2',
    '待办弹窗提醒',
    description: '在待办截止时间显示顶部弹窗或锁屏提醒',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'todo_reminder_alerts_v2',
      '待办弹窗提醒',
      channelDescription: '在待办截止时间显示顶部弹窗或锁屏提醒',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      ticker: '待办时间到了',
    ),
  );

  final _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<void> initialize() async {
    try {
      tz_data.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
      );
      await _android?.createNotificationChannel(_channel);
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  @override
  void bindDeliveryRepository(RuntimeReminderDeliveryRepository? repository) {}

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _android;
      if (!_initialized || android == null) return false;
      var enabled = await android.areNotificationsEnabled() == true;
      if (!enabled) {
        enabled = await android.requestNotificationsPermission() == true;
      }
      if (!enabled) return false;
      var exact = await android.canScheduleExactNotifications() == true;
      if (!exact) exact = await android.requestExactAlarmsPermission() == true;
      if (!exact) return false;
      return await android.requestFullScreenIntentPermission() == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      final android = _android;
      if (!_initialized || android == null) return false;
      if (await android.areNotificationsEnabled() == true) return true;
      return await android.requestNotificationsPermission() == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> syncReminders(Iterable<Todo> todos) async {
    if (!_initialized) return;
    try {
      final pending = await _notifications.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.payload?.startsWith('todo:') == true) {
          await _notifications.cancel(id: notification.id);
        }
      }
      await _deleteLegacyChannels();
      final android = _android;
      if (android == null ||
          await android.areNotificationsEnabled() != true ||
          await android.canScheduleExactNotifications() != true) {
        return;
      }
      final now = DateTime.now();
      for (final todo in todos) {
        if (todo.reminderEnabled &&
            !todo.isCompleted &&
            !todo.isDeleted &&
            todo.dueAt.isAfter(now)) {
          await _schedule(todo);
        }
      }
    } catch (_) {}
  }

  Future<void> _deleteLegacyChannels() async {
    final android = _android;
    if (android == null) return;
    for (final channelId in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(channelId: channelId);
      } catch (_) {}
    }
  }

  @override
  Future<void> cancel(String todoId) async {
    if (!_initialized) return;
    try {
      await _notifications.cancel(id: notificationId(todoId));
    } catch (_) {}
  }

  @override
  Future<bool> openNotificationSettings() async {
    try {
      return await _android?.openAppNotificationSettings() ?? false;
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
        title: '待办提醒测试',
        body: '如果看到弹窗并听到声音或感到振动，说明提醒设置正常',
        notificationDetails: _details,
        payload: 'todo:test',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _schedule(Todo todo) => _notifications.zonedSchedule(
    id: notificationId(todo.id),
    title: todo.title,
    body: todo.description.isEmpty ? '待办时间到了' : todo.description,
    scheduledDate: tz.TZDateTime(
      tz.local,
      todo.dueAt.year,
      todo.dueAt.month,
      todo.dueAt.day,
      todo.dueAt.hour,
      todo.dueAt.minute,
    ),
    notificationDetails: _details,
    androidScheduleMode: AndroidScheduleMode.alarmClock,
    payload: 'todo:${todo.id}',
  );

  @override
  Future<void> resume(Iterable<Todo> todos) async {}

  @override
  Future<void> dispose() async {}
}

int notificationId(String todoId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in todoId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
