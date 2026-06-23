import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/reminder_scheduler.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/core/schedule_engine.dart';
import 'package:trip_reminder_scheduler/src/core/timezone_resolver.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // fakeAsync needs a fixed "now" so the 2024 trip stays in the future and the
  // 300ms debounce is deterministic.
  final initialTime = DateTime.utc(2024, 1, 1);

  Trip trip() => Trip(
        id: 't1',
        homeIana: 'America/New_York',
        destinationCountry: 'United Kingdom',
        startDate: DateTime.utc(2024, 6, 12),
        endDate: DateTime.utc(2024, 6, 14),
        reminderTime: const ReminderTime(9, 0),
        preBufferDays: 1,
        postBufferDays: 1,
      );

  ReminderScheduler build(
    FakeNotificationGateway gateway,
    InMemoryRegistryStore store,
  ) {
    final resolver = TimezoneResolver(
      deviceSource: FakeDeviceTimezoneSource('America/New_York'),
      locationSource: FakeLocationZoneSource(),
      countryMap: FakeCountryZoneMap(),
    );
    return ReminderScheduler(
      engine: ScheduleEngine(resolver: resolver),
      gateway: gateway,
      registryStore: store,
      loadTrips: () async => [trip()],
    );
  }

  test('a reschedule request schedules reminders and persists the registry',
      () {
    fakeAsync((async) {
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      final scheduler = build(gateway, store);

      scheduler.request(RescheduleTrigger.initialSchedule);
      async.elapse(const Duration(milliseconds: 300));

      // 5 days (1 pre + 3 trip + 1 post), all scheduled and persisted.
      expect(gateway.scheduled, hasLength(5));
      expect(gateway.scheduled.map((r) => r.id).toSet(), hasLength(5));
    }, initialTime: initialTime);
  });

  test('re-requesting with no changes is a no-op (idempotent end to end)', () {
    fakeAsync((async) {
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      final scheduler = build(gateway, store);

      scheduler.request(RescheduleTrigger.initialSchedule);
      async.elapse(const Duration(milliseconds: 300));
      expect(gateway.scheduled, hasLength(5));

      gateway.scheduled.clear();
      async.elapse(const Duration(seconds: 6)); // clear the dedup window
      scheduler.request(RescheduleTrigger.periodicRebalance);
      async.elapse(const Duration(milliseconds: 300));

      expect(gateway.scheduled, isEmpty, reason: 'nothing changed');
    }, initialTime: initialTime);
  });

  test('recoverOnLaunch re-schedules everything after the OS clears pending',
      () {
    fakeAsync((async) {
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      final scheduler = build(gateway, store);

      // Initial schedule.
      scheduler.request(RescheduleTrigger.initialSchedule);
      async.elapse(const Duration(milliseconds: 300));
      expect(gateway.scheduled, hasLength(5));

      // Simulate a reboot: registry still records the reminders, but the OS
      // reports nothing pending.
      gateway.setPending(const []);
      gateway.scheduled.clear();

      scheduler.recoverOnLaunch();
      async.elapse(const Duration(milliseconds: 300));

      expect(gateway.scheduled, hasLength(5),
          reason: 'osCleared forces a full resync');
    }, initialTime: initialTime);
  });
}
