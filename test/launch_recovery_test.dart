import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/core/launch_recovery.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/resolved_zone.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const recovery = LaunchRecovery();

  ScheduledReminder sample({String iana = 'America/New_York'}) =>
      ScheduledReminder(
        id: 1,
        fireInstantUtc: DateTime.utc(2024, 6, 12, 13, 0),
        iana: iana,
        source: ZoneSource.deviceTimezone,
        confidence: ZoneConfidence.medium,
        trigger: RescheduleTrigger.initialSchedule,
        tripId: 't1',
        dayIndex: 0,
        wallClock: const ReminderTime(9, 0),
        scheduledAtUtc: DateTime.utc(2024, 6, 1),
      );

  ReminderRegistry registry({
    required DateTime? lastScheduleAtUtc,
    String? lastZoneId = 'America/New_York',
    bool withReminder = true,
  }) =>
      ReminderRegistry(
        reminders: withReminder ? [sample()] : const [],
        lastZoneId: lastZoneId,
        lastScheduleAtUtc: lastScheduleAtUtc,
      );

  final now = DateTime.utc(2024, 6, 12, 12, 0);

  test('OS-cleared: registry has reminders but nothing is pending', () {
    final t = recovery.decide(
      registry: registry(lastScheduleAtUtc: now.subtract(const Duration(hours: 1))),
      pendingIds: const [],
      now: now,
    );
    expect(t, RescheduleTrigger.osCleared);
  });

  test('fresh install (never scheduled) is a cold start', () {
    final t = recovery.decide(
      registry: ReminderRegistry.empty,
      pendingIds: const [],
      now: now,
    );
    expect(t, RescheduleTrigger.coldStart);
  });

  test('cold start when the last schedule is older than 6h', () {
    final t = recovery.decide(
      registry: registry(lastScheduleAtUtc: now.subtract(const Duration(hours: 7))),
      pendingIds: const [1], // still pending, so not OS-cleared
      now: now,
    );
    expect(t, RescheduleTrigger.coldStart);
  });

  test('periodic rebalance after more than 20 days', () {
    final t = recovery.decide(
      registry: registry(lastScheduleAtUtc: now.subtract(const Duration(days: 21))),
      pendingIds: const [1],
      now: now,
    );
    expect(t, RescheduleTrigger.periodicRebalance);
  });

  test('DST transition detected within the cold-start window', () {
    // Last scheduled at 01:00 EDT (UTC-4); now 03:00 EST (UTC-5), 3h later.
    final last = DateTime.utc(2024, 11, 3, 5, 0);
    final dstNow = DateTime.utc(2024, 11, 3, 8, 0);
    final t = recovery.decide(
      registry: registry(lastScheduleAtUtc: last),
      pendingIds: const [1],
      now: dstNow,
    );
    expect(t, RescheduleTrigger.dstTransition);
  });

  test('fresh and intact within the window returns null (no-op)', () {
    final t = recovery.decide(
      registry: registry(lastScheduleAtUtc: now.subtract(const Duration(hours: 1))),
      pendingIds: const [1],
      now: now,
    );
    expect(t, isNull);
  });
}
