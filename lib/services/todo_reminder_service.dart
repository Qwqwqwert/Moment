import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/todo.dart';

class TodoReminderService {
  static const _legacyChannelIds = ['todo_reminders'];
  static const _channel = AndroidNotificationChannel(
    'todo_reminder_alerts_v2',
    '待办弹窗提醒',
    description: '在待办截止时间显示顶部弹窗或锁屏提醒',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  static const _notificationDetails = NotificationDetails(
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

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> requestPermission() async {
    try {
      final android = _android;
      if (!_initialized || android == null) return false;

      var notificationsEnabled =
          await android.areNotificationsEnabled() == true;
      if (!notificationsEnabled) {
        notificationsEnabled =
            await android.requestNotificationsPermission() == true;
      }
      if (!notificationsEnabled) return false;

      var exactAlarmsEnabled =
          await android.canScheduleExactNotifications() == true;
      if (!exactAlarmsEnabled) {
        exactAlarmsEnabled =
            await android.requestExactAlarmsPermission() == true;
      }
      if (!exactAlarmsEnabled) return false;

      return await android.requestFullScreenIntentPermission() == true;
    } catch (_) {
      return false;
    }
  }

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
    } catch (_) {
      // A revoked system permission must not prevent the app from loading data.
    }
  }

  Future<void> _deleteLegacyChannels() async {
    final android = _android;
    if (android == null) return;
    for (final channelId in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(channelId: channelId);
      } catch (_) {
        // A missing legacy channel is already in the desired state.
      }
    }
  }

  Future<void> cancel(String todoId) async {
    if (!_initialized) return;
    try {
      await _notifications.cancel(id: _notificationId(todoId));
    } catch (_) {
      // The todo operation should still succeed if Android rejects cancellation.
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _android?.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showTestReminder() async {
    if (!_initialized) return false;
    try {
      await _notifications.show(
        id: 2147483000,
        title: '待办提醒测试',
        body: '如果看到弹窗并听到声音或感到振动，说明提醒设置正常',
        notificationDetails: _notificationDetails,
        payload: 'todo:test',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _schedule(Todo todo) {
    final dueAt = todo.dueAt;
    final scheduledAt = tz.TZDateTime(
      tz.local,
      dueAt.year,
      dueAt.month,
      dueAt.day,
      dueAt.hour,
      dueAt.minute,
    );
    return _notifications.zonedSchedule(
      id: _notificationId(todo.id),
      title: todo.title,
      body: todo.description.isEmpty ? '待办时间到了' : todo.description,
      scheduledDate: scheduledAt,
      notificationDetails: _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: 'todo:${todo.id}',
    );
  }

  int _notificationId(String todoId) {
    var hash = 0x811c9dc5;
    for (final codeUnit in todoId.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
