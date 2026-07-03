import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/todo.dart';

/// Erinnerungen als System-Benachrichtigungen.
///
/// v1: nur Android (AlarmManager-basierte Planung, funktioniert auch bei
/// geschlossener App). Auf Windows zeigt die UI Fälligkeiten an.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get isSupported => Platform.isAndroid;

  Future<void> init() async {
    if (!isSupported) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(
          tz.getLocation(await FlutterTimezone.getLocalTimezone()));
    } catch (_) {
      // Fallback: UTC — Erinnerungen kommen dann ggf. verschoben.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _ready = true;
  }

  /// Stabile Notification-ID je (ToDo, Erinnerungs-Index).
  int _notificationId(String todoId, int index) =>
      (todoId.hashCode ^ (index * 7919)) & 0x7fffffff;

  /// Plant alle zukünftigen Erinnerungen eines ToDos (ersetzt bestehende).
  Future<void> scheduleForTodo(Todo todo) async {
    if (!_ready) return;
    await cancelForTodo(todo);
    if (todo.isDone) return;
    for (var i = 0; i < todo.reminders.length; i++) {
      final at = todo.reminders[i];
      if (at.isBefore(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        id: _notificationId(todo.id, i),
        title: todo.title,
        body: todo.due == null ? 'Erinnerung' : 'Fällig: ${_formatDue(todo)}',
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Erinnerungen',
            channelDescription: 'Erinnerungen an fällige ToDos',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelForTodo(Todo todo) async {
    if (!_ready) return;
    // Großzügig alle möglichen Erinnerungs-Slots aufräumen.
    for (var i = 0; i < 10; i++) {
      await _plugin.cancel(id: _notificationId(todo.id, i));
    }
  }

  String _formatDue(Todo todo) {
    final d = todo.due!;
    final date =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    if (!todo.dueHasTime) return date;
    return '$date, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} Uhr';
  }
}
