import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/core/schedule_engine.dart';
import 'package:trip_reminder_scheduler/src/core/timezone_resolver.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  TimezoneResolver resolver() => TimezoneResolver(
        deviceSource: FakeDeviceTimezoneSource('America/New_York'),
        locationSource: FakeLocationZoneSource(),
        countryMap: FakeCountryZoneMap(),
      );

  final now = DateTime.utc(2024, 1, 1); // everything below is in the future

  Trip trip(String id) => Trip(
        id: id,
        homeIana: 'America/New_York',
        destinationCountry: 'United Kingdom',
        startDate: DateTime.utc(2024, 6, 12),
        endDate: DateTime.utc(2024, 6, 14),
        reminderTime: const ReminderTime(9, 0),
        preBufferDays: 1,
        postBufferDays: 1,
      );

  test('deterministicId does not collide across trips (no shared ranges)', () {
    // Two trip ids differing by one character used to make their rolling hashes
    // differ by 1, which collided day 31 of one with day 0 of the other. Verify
    // a dense span of (tripId, dayIndex) pairs is collision-free for such ids.
    const a = '1718000000000000';
    const b = '1718000000000001';
    expect(
      ScheduleEngine.deterministicId(a, 31),
      isNot(ScheduleEngine.deterministicId(b, 0)),
    );
    final ids = <int>{};
    for (final id in [a, b]) {
      for (var day = 0; day < 64; day++) {
        expect(ids.add(ScheduleEngine.deterministicId(id, day)), isTrue,
            reason: 'collision at $id#$day');
      }
    }
  });

  test('re-running with identical inputs produces no duplicates', () async {
    final engine = ScheduleEngine(resolver: resolver());

    final first = await engine.reconcile(
      registry: ReminderRegistry.empty,
      trips: [trip('t1')],
      now: now,
      trigger: RescheduleTrigger.initialSchedule,
    );
    expect(first.plan.toSchedule, hasLength(5));
    expect(first.plan.toCancel, isEmpty);

    final second = await engine.reconcile(
      registry: first.registry,
      trips: [trip('t1')],
      now: now,
      trigger: RescheduleTrigger.periodicRebalance,
    );
    expect(second.plan.isNoop, isTrue);
    expect(second.plan.toSchedule, isEmpty);
    expect(second.plan.toCancel, isEmpty);
    expect(second.plan.unchanged, hasLength(5));
  });

  test('changing the reminder time reschedules exactly those ids', () async {
    final engine = ScheduleEngine(resolver: resolver());
    final first = await engine.reconcile(
      registry: ReminderRegistry.empty,
      trips: [trip('t1')],
      now: now,
      trigger: RescheduleTrigger.initialSchedule,
    );

    final edited = trip('t1').copyWith(reminderTime: const ReminderTime(10, 0));
    final second = await engine.reconcile(
      registry: first.registry,
      trips: [edited],
      now: now,
      trigger: RescheduleTrigger.userEdit,
    );

    // Ids are stable (derived from trip + day), so nothing is cancelled; every
    // reminder's instant changed, so every id is rescheduled.
    expect(second.plan.toCancel, isEmpty);
    expect(second.plan.unchanged, isEmpty);
    expect(
      second.plan.toSchedule.map((r) => r.id).toSet(),
      first.registry.ids.toSet(),
    );
  });

  test('removing a trip cancels exactly that trip\'s ids', () async {
    final engine = ScheduleEngine(resolver: resolver());
    final both = await engine.reconcile(
      registry: ReminderRegistry.empty,
      trips: [trip('A'), trip('B')],
      now: now,
      trigger: RescheduleTrigger.initialSchedule,
    );
    final idsA = both.registry.reminders
        .where((r) => r.tripId == 'A')
        .map((r) => r.id)
        .toSet();
    final idsB = both.registry.reminders
        .where((r) => r.tripId == 'B')
        .map((r) => r.id)
        .toSet();

    final onlyA = await engine.reconcile(
      registry: both.registry,
      trips: [trip('A')],
      now: now,
      trigger: RescheduleTrigger.userEdit,
    );
    expect(onlyA.plan.toCancel.toSet(), idsB);
    expect(onlyA.plan.unchanged.toSet(), idsA);
    expect(onlyA.plan.toSchedule, isEmpty);
  });

  test('the cap is enforced, keeping the soonest reminders', () async {
    final engine = ScheduleEngine(resolver: resolver(), maxScheduled: 10);
    final longTrip = Trip(
      id: 'long',
      homeIana: 'America/New_York',
      destinationCountry: 'United Kingdom',
      startDate: DateTime.utc(2024, 6, 1),
      endDate: DateTime.utc(2024, 7, 30), // ~60 days
      reminderTime: const ReminderTime(9, 0),
    );

    final result = await engine.reconcile(
      registry: ReminderRegistry.empty,
      trips: [longTrip],
      now: now,
      trigger: RescheduleTrigger.initialSchedule,
    );

    expect(result.registry.reminders, hasLength(10));
    final keptDays = result.registry.reminders.map((r) => r.dayIndex).toList()
      ..sort();
    expect(keptDays, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        reason: 'soonest-first');
  });

  test('same-minute collisions are nudged apart', () async {
    final engine = ScheduleEngine(resolver: resolver());
    // Two single-day trips at the same destination, same reminder time -> both
    // resolve to 08:00 UTC on the same day.
    Trip oneDay(String id) => Trip(
          id: id,
          homeIana: 'America/New_York',
          destinationCountry: 'United Kingdom',
          startDate: DateTime.utc(2024, 6, 12),
          endDate: DateTime.utc(2024, 6, 12),
          reminderTime: const ReminderTime(9, 0),
        );

    final result = await engine.reconcile(
      registry: ReminderRegistry.empty,
      trips: [oneDay('A'), oneDay('B')],
      now: now,
      trigger: RescheduleTrigger.initialSchedule,
    );

    expect(result.registry.reminders, hasLength(2));
    final a = result.registry.reminders.firstWhere((r) => r.tripId == 'A');
    final b = result.registry.reminders.firstWhere((r) => r.tripId == 'B');
    expect(a.fireInstantUtc, isNot(b.fireInstantUtc));
    expect(a.fireInstantUtc.difference(b.fireInstantUtc).abs(),
        const Duration(seconds: 5));
  });
}
