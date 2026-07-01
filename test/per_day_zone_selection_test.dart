import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/resolved_zone.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/core/schedule_engine.dart';
import 'package:trip_reminder_scheduler/src/core/timezone_resolver.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // Home New York, destination United Kingdom (Europe/London).
  ScheduleEngine engineWith({String? location}) => ScheduleEngine(
        resolver: TimezoneResolver(
          deviceSource: FakeDeviceTimezoneSource('America/New_York'),
          locationSource: FakeLocationZoneSource(location),
          countryMap: FakeCountryZoneMap(),
        ),
      );

  Trip nyToLondon() => Trip(
        id: 't1',
        homeIana: 'America/New_York',
        destinationCountry: 'United Kingdom',
        startDate: DateTime.utc(2024, 6, 12),
        endDate: DateTime.utc(2024, 6, 14),
        reminderTime: const ReminderTime(9, 0),
        preBufferDays: 1,
        postBufferDays: 1,
      );

  ScheduledReminder byDay(List<ScheduledReminder> rs, int dayIndex) =>
      rs.firstWhere((r) => r.dayIndex == dayIndex);

  test('buffer days use home, trip days use destination', () async {
    final engine = engineWith();
    final cands = await engine.candidatesFor(
      nyToLondon(),
      now: DateTime.utc(2024, 6, 1), // well before the trip; nothing is "today"
      trigger: RescheduleTrigger.initialSchedule,
    );

    expect(byDay(cands, 0).iana, 'America/New_York', reason: 'pre-buffer day');
    expect(byDay(cands, 0).source, ZoneSource.userChosen);

    expect(byDay(cands, 1).iana, 'Europe/London', reason: 'first trip day');
    expect(byDay(cands, 1).source, ZoneSource.countryHeuristic);
    expect(byDay(cands, 2).iana, 'Europe/London');
    expect(byDay(cands, 3).iana, 'Europe/London', reason: 'last trip day');

    expect(byDay(cands, 4).iana, 'America/New_York', reason: 'post-buffer day');
  });

  test('today + high-confidence live location overrides the phase zone',
      () async {
    final engine = engineWith(location: 'Asia/Dubai');
    // now is the morning of 2024-06-12 in New York (home), so day index 1 is
    // "today" — and it is a destination day, which the live zone overrides.
    final cands = await engine.candidatesFor(
      nyToLondon(),
      now: DateTime.utc(2024, 6, 12, 4, 30),
      trigger: RescheduleTrigger.locationChanged,
    );

    final today = byDay(cands, 1);
    expect(today.iana, 'Asia/Dubai', reason: 'live location wins for today');
    expect(today.source, ZoneSource.liveLocation);

    // Other days are unaffected by the live signal.
    expect(byDay(cands, 2).iana, 'Europe/London');
    expect(byDay(cands, 4).iana, 'America/New_York');
  });

  test('today without a live signal falls through to the phase zone', () async {
    final engine = engineWith(); // no location
    final cands = await engine.candidatesFor(
      nyToLondon(),
      now: DateTime.utc(2024, 6, 12, 4, 30),
      trigger: RescheduleTrigger.coldStart,
    );
    // day index 1 is "today" but with no live signal it stays a destination day
    expect(byDay(cands, 1).iana, 'Europe/London');
    expect(byDay(cands, 1).source, ZoneSource.countryHeuristic);
  });

  test('reminders are scheduled as absolute UTC instants', () async {
    final engine = engineWith();
    final cands = await engine.candidatesFor(
      nyToLondon(),
      now: DateTime.utc(2024, 6, 1),
      trigger: RescheduleTrigger.initialSchedule,
    );
    // Day 2 (2024-06-13) is a London day; 09:00 BST == 08:00 UTC.
    expect(byDay(cands, 2).fireInstantUtc, DateTime.utc(2024, 6, 13, 8, 0));
    // Day 4 (2024-06-15) is a New York day; 09:00 EDT == 13:00 UTC.
    expect(byDay(cands, 4).fireInstantUtc, DateTime.utc(2024, 6, 15, 13, 0));
  });
}
