import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/models/scheduled_reminder.dart';
import '../core/ports/notification_gateway.dart';

/// [NotificationGateway] backed by `flutter_local_notifications`.
///
/// This is the only place that turns a [ScheduledReminder] into a real pending
/// OS notification. It schedules against an absolute [tz.TZDateTime] built from
/// the reminder's UTC instant — the OS fires at that instant regardless of any
/// later device-timezone change, which is the whole point of storing instants.
class FlutterNotificationGateway implements NotificationGateway {
  FlutterNotificationGateway(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const String channelId = 'trip_reminders';
  static const String channelName = 'Trip reminders';

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Timezone-aware daily trip reminders',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  @override
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  }) async {
    final scheduledDate =
        tz.TZDateTime.from(reminder.fireInstantUtc, _location(reminder.iana));
    await _plugin.zonedSchedule(
      id: reminder.id,
      scheduledDate: scheduledDate,
      notificationDetails: _details,
      // Exact even in Doze; the reminder is time-critical.
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<List<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((p) => p.id).toList();
  }

  tz.Location _location(String iana) {
    try {
      return tz.getLocation(iana);
    } catch (_) {
      return tz.UTC;
    }
  }
}
