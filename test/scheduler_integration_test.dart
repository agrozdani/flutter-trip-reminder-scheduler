import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/reminder_scheduler.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
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
    InMemoryRegistryStore store, {
    List<Trip> Function()? trips,
  }) {
    final resolver = TimezoneResolver(
      deviceSource: FakeDeviceTimezoneSource('America/New_York'),
      locationSource: FakeLocationZoneSource(),
      countryMap: FakeCountryZoneMap(),
    );
    return ReminderScheduler(
      engine: ScheduleEngine(resolver: resolver),
      gateway: gateway,
      registryStore: store,
      loadTrips: () async => trips?.call() ?? [trip()],
    );
  }

  // A scheduler that has already scheduled the trip's five reminders, standing
  // in for an earlier run of the app. The store and gateway outlive it, as
  // the persisted registry and the OS do.
  void scheduleInEarlierProcess(
    FakeAsync async,
    FakeNotificationGateway gateway,
    InMemoryRegistryStore store,
  ) {
    build(gateway, store).request(RescheduleTrigger.userEdit);
    async.elapse(const Duration(milliseconds: 300));
    expect(gateway.scheduled, hasLength(5));
    gateway.scheduled.clear();
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

      // Simulate the OS losing its pending set: the registry still records
      // the reminders, but the OS reports nothing pending.
      gateway.setPending(const []);
      gateway.scheduled.clear();

      scheduler.recoverOnLaunch();
      async.elapse(const Duration(milliseconds: 300));

      expect(gateway.scheduled, hasLength(5),
          reason: 'osCleared forces a full resync');
      expect(gateway.cancelled, isEmpty,
          reason: 'nothing is pending, and a cancel would also dismiss '
              'delivered notifications');
    }, initialTime: initialTime);
  });

  test('a new process hands the whole schedule back, then goes back to diffs',
      () {
    fakeAsync((async) {
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      scheduleInEarlierProcess(async, gateway, store);

      // Relaunch minutes later. The registry is fresh and the gateway still
      // lists all five as pending — exactly what Android's plugin reports after
      // a force-stop has cleared the real alarms — so neither launch recovery
      // nor the diff sees anything to do.
      async.elapse(const Duration(minutes: 5));
      final relaunched = build(gateway, store);
      RescheduleTrigger? recovery = RescheduleTrigger.osCleared;
      relaunched.recoverOnLaunch().then((t) => recovery = t);
      async.elapse(const Duration(milliseconds: 300));

      expect(recovery, isNull, reason: 'nothing looked wrong');
      expect(gateway.scheduled.map((r) => r.id).toSet(), store.current.ids.toSet(),
          reason: 'the first run of a process re-asserts every reminder');
      expect(gateway.scheduled, hasLength(5));
      expect(gateway.cancelled, isEmpty);

      // Once per process: the next run is an ordinary diff again.
      gateway.scheduled.clear();
      async.elapse(const Duration(seconds: 6)); // clear the dedup window
      relaunched.request(RescheduleTrigger.appResume);
      async.elapse(const Duration(milliseconds: 300));
      expect(gateway.scheduled, isEmpty);
    }, initialTime: initialTime);
  });

  test('a process\'s first run still cancels what is no longer wanted', () {
    fakeAsync((async) {
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      scheduleInEarlierProcess(async, gateway, store);
      final ids = store.current.ids.toSet();

      // The trip is gone by the time the new process first runs.
      build(gateway, store, trips: () => const [])
          .request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));

      expect(gateway.cancelled.toSet(), ids);
      expect(gateway.scheduled, isEmpty);
    }, initialTime: initialTime);
  });

  test('a failed first run leaves the hand-over owed to the next run', () {
    fakeAsync((async) {
      final gateway = _FailsOnceGateway();
      final store = InMemoryRegistryStore();
      scheduleInEarlierProcess(async, gateway, store);

      final relaunched = build(gateway, store);
      gateway.failNext = true;
      Object? error;
      relaunched.recoverOnLaunch().catchError((Object e) {
        error = e;
        return null;
      });
      async.elapse(const Duration(milliseconds: 300));
      expect(error, isA<StateError>());

      gateway.scheduled.clear();
      relaunched.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));
      expect(gateway.scheduled, hasLength(5));
    }, initialTime: initialTime);
  });
}

/// Rejects one schedule call when [failNext] is set, then behaves normally.
class _FailsOnceGateway extends FakeNotificationGateway {
  bool failNext = false;

  @override
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('the OS rejected the schedule');
    }
    return super.schedule(reminder, title: title, body: body);
  }
}
