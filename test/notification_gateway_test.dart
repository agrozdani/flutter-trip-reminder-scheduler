import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/resolved_zone.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
import 'package:trip_reminder_scheduler/src/core/wall_clock.dart';
import 'package:trip_reminder_scheduler/src/platform/flutter_notification_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  setUpAll(tzdata.initializeTimeZones);

  test('a fall-back overlap reminder reaches the platform as one exact instant',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    // 01:30 happens twice in New York on 2024-11-03; WallClock picks the later,
    // standard-time occurrence: 06:30 UTC.
    final fire = WallClock.toInstant(
            tz.getLocation('America/New_York'), 2024, 11, 3, 1, 30)
        .toUtc();
    expect(fire, DateTime.utc(2024, 11, 3, 6, 30));
    final reminder = ScheduledReminder(
      id: 7,
      fireInstantUtc: fire,
      iana: 'America/New_York',
      source: ZoneSource.userChosen,
      confidence: ZoneConfidence.high,
      trigger: RescheduleTrigger.userEdit,
      tripId: 't1',
      dayIndex: 0,
      wallClock: const ReminderTime(1, 30),
      scheduledAtUtc: DateTime.utc(2024, 1, 1),
    );

    await withClock(Clock.fixed(DateTime.utc(2024, 1, 1)), () {
      return FlutterNotificationGateway(FlutterLocalNotificationsPlugin())
          .schedule(reminder, title: 'title', body: 'body');
    });

    // The platform rebuilds the instant from this (wall time, zone) pair.
    // "01:30 America/New_York" would be ambiguous — Android resolves it to the
    // earlier 05:30 UTC — whereas a UTC wall time names exactly one instant.
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(calls.single.method, 'zonedSchedule');
    expect(args['timeZoneName'], 'UTC');
    expect(args['scheduledDateTime'], '2024-11-03T06:30:00');
  });
}
