import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/models/scheduled_reminder.dart';
import '../core/ports/notification_gateway.dart';

/// [NotificationGateway] backed by `flutter_local_notifications`.
///
/// This is the only place that turns a [ScheduledReminder] into a real pending
/// OS notification. It hands the plugin the reminder's absolute instant
/// expressed in UTC — the OS fires at that instant regardless of any later
/// device-timezone change, which is the whole point of storing instants.
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
    // Express the instant in UTC, not the reminder's zone. The plugin sends the
    // platform a wall-clock string plus a zone name and lets it rebuild the
    // instant; on a fall-back day that pair names two instants, and the
    // platform picks its own (Android's ZonedDateTime.of takes the earlier),
    // undoing WallClock's later-occurrence choice. UTC has no DST, so the pair
    // names exactly one instant.
    final scheduledDate =
        tz.TZDateTime.from(reminder.fireInstantUtc, tz.getLocation('UTC'));
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
  Future<List<int>> pendingIds() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((p) => p.id).toList();
  }
}
