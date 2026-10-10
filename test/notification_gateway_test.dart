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

  // Routes the plugin to its Android implementation and records every call it
  // makes over the platform channel.
  List<MethodCall> recordAndroidCalls() {
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
    return calls;
  }

  ScheduledReminder reminderAt(DateTime fire) => ScheduledReminder(
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

  Future<void> scheduleAt(DateTime now, ScheduledReminder reminder) =>
      withClock(Clock.fixed(now), () {
        return FlutterNotificationGateway(FlutterLocalNotificationsPlugin())
            .schedule(reminder, title: 'title', body: 'body');
      });

  test('a fall-back overlap reminder reaches the platform as one exact instant',
      () async {
    final calls = recordAndroidCalls();

    // 01:30 happens twice in New York on 2024-11-03; WallClock picks the later,
    // standard-time occurrence: 06:30 UTC.
    final fire = WallClock.toInstant(
            tz.getLocation('America/New_York'), 2024, 11, 3, 1, 30)
        .toUtc();
    expect(fire, DateTime.utc(2024, 11, 3, 6, 30));

    await scheduleAt(DateTime.utc(2024, 1, 1), reminderAt(fire));

    // The platform rebuilds the instant from this (wall time, zone) pair.
    // "01:30 America/New_York" would be ambiguous — Android resolves it to the
    // earlier 05:30 UTC — whereas a UTC wall time names exactly one instant.
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(calls.single.method, 'zonedSchedule');
    expect(args['timeZoneName'], 'UTC');
    expect(args['scheduledDateTime'], '2024-11-03T06:30:00');
  });

  test('an instant that comes due mid-run fires right away, under its own id',
      () async {
    final calls = recordAndroidCalls();
    final fire = DateTime.utc(2024, 6, 12, 9, 0);

    // A second after the instant, the plugin would reject it as a past date
    // and abort the run. Instead it goes out two seconds from now, replacing
    // any older pending entry with the same id.
    await scheduleAt(fire.add(const Duration(seconds: 1)), reminderAt(fire));

    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['id'], 7);
    expect(args['timeZoneName'], 'UTC');
    expect(args['scheduledDateTime'], '2024-06-12T09:00:03');

    // Still half a second ahead is too close to call: it goes out two seconds
    // from now as well.
    calls.clear();
    await scheduleAt(
        fire.subtract(const Duration(milliseconds: 500)), reminderAt(fire));
    expect((calls.single.arguments as Map)['scheduledDateTime'],
        '2024-06-12T09:00:01');
  });
}
