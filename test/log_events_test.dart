import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/reminder_scheduler.dart';
import 'package:trip_reminder_scheduler/src/app/report_error.dart';
import 'package:trip_reminder_scheduler/src/core/logging.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/core/schedule_engine.dart';
import 'package:trip_reminder_scheduler/src/core/timezone_resolver.dart';
import 'package:trip_reminder_scheduler/src/platform/prefs_registry_store.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final initialTime = DateTime.utc(2024, 1, 1);

  Trip trip({String country = 'United Kingdom'}) => Trip(
    id: 't1',
    homeIana: 'America/New_York',
    destinationCountry: country,
    startDate: DateTime.utc(2024, 6, 12),
    endDate: DateTime.utc(2024, 6, 14),
    reminderTime: const ReminderTime(9, 0),
    preBufferDays: 1,
    postBufferDays: 1,
  );

  ScheduleEngine engine(Logger log, {int maxScheduled = 64}) => ScheduleEngine(
    resolver: TimezoneResolver(
      deviceSource: FakeDeviceTimezoneSource('America/New_York'),
      locationSource: FakeLocationZoneSource(),
      countryMap: FakeCountryZoneMap(),
    ),
    maxScheduled: maxScheduled,
    log: log.tagged('engine'),
  );

  ReminderScheduler scheduler(
    Logger log,
    FakeNotificationGateway gateway,
    InMemoryRegistryStore store,
  ) => ReminderScheduler(
    engine: engine(log),
    gateway: gateway,
    registryStore: store,
    loadTrips: () async => [trip()],
    log: log.tagged('scheduler'),
  );

  Iterable<LogRecord> events(LogBuffer buffer, String event) =>
      buffer.records.where((r) => r.event == event);

  test('a reschedule logs what it did, and a skipped repeat says why', () {
    fakeAsync((async) {
      final buffer = LogBuffer();
      final gateway = FakeNotificationGateway();
      final s = scheduler(Logger([buffer]), gateway, InMemoryRegistryStore());

      s.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));
      s.request(RescheduleTrigger.appResume); // inside the 5 s dedup window
      async.elapse(const Duration(milliseconds: 300));

      final done = events(buffer, 'run.done').single;
      expect(done.tag, 'scheduler');
      expect(done.level, LogLevel.info);
      expect(done.fields, {
        'run': 1,
        'trigger': RescheduleTrigger.userEdit,
        'handOver': true,
        'trips': 1,
        'toCancel': 0,
        'toSchedule': 5,
        'cancelled': 0,
        'scheduled': 5,
        'unchanged': 0,
        'registered': 5,
        'took': Duration.zero,
      });

      final skipped = events(buffer, 'skipped').single;
      expect(skipped.tag, 'coordinator');
      expect(skipped.fields['trigger'], RescheduleTrigger.appResume);
      expect(skipped.fields['sinceLastRun'], const Duration(milliseconds: 300));
    }, initialTime: initialTime);
  });

  test('a run that fails partway logs where it stopped and what it did', () {
    fakeAsync((async) {
      final buffer = LogBuffer();
      final gateway = _FailingGateway(failAfter: 2);
      scheduler(
        Logger([buffer]),
        gateway,
        InMemoryRegistryStore(),
      ).request(RescheduleTrigger.userEdit).catchError((Object _) {});
      async.elapse(const Duration(milliseconds: 300));

      final failed = events(buffer, 'run.failed').single;
      expect(failed.level, LogLevel.error);
      expect(failed.fields['stage'], 'apply');
      expect(failed.fields['toSchedule'], 5);
      expect(failed.fields['scheduled'], 2);
      expect(failed.error, isA<StateError>());
      expect(failed.stackTrace, isNotNull);
      expect(events(buffer, 'run.done'), isEmpty);
    }, initialTime: initialTime);
  });

  test('launch logs its recovery reason against what the OS reports', () {
    fakeAsync((async) {
      final buffer = LogBuffer();
      final gateway = FakeNotificationGateway();
      final store = InMemoryRegistryStore();
      final s = scheduler(Logger([buffer]), gateway, store);
      s.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));

      gateway.setPending(const []); // the OS lost them
      s.recoverOnLaunch();
      async.elapse(const Duration(milliseconds: 300));

      expect(events(buffer, 'launch').single.fields, {
        'reason': RescheduleTrigger.osCleared,
        'registered': 5,
        'pending': 0,
        'lastScheduleAt': initialTime.add(const Duration(milliseconds: 300)),
        'lastZone': store.current.lastZoneId,
      });
    }, initialTime: initialTime);
  });

  test(
    'the engine warns when a zone falls back or the cap drops some',
    () async {
      final buffer = LogBuffer();
      await engine(Logger([buffer]), maxScheduled: 2).reconcile(
        registry: ReminderRegistry.empty,
        trips: [trip(country: 'Atlantis')],
        now: initialTime,
        trigger: RescheduleTrigger.userEdit,
      );

      final fallback = events(buffer, 'zone.destination.fallback').single;
      expect(fallback.level, LogLevel.warning);
      expect(fallback.fields['country'], 'Atlantis');
      expect(fallback.fields['got'], 'America/New_York(deviceTimezone,medium)');

      final cap = events(buffer, 'cap').single;
      expect(cap.level, LogLevel.warning);
      expect(cap.fields['wanted'], 5);
      expect(cap.fields['kept'], 2);
    },
  );

  test('an unreadable registry is logged, not dropped silently', () async {
    SharedPreferences.setMockInitialValues({'reminder_registry_v1': '{"oops'});
    final buffer = LogBuffer();
    final store = PrefsRegistryStore(
      await SharedPreferences.getInstance(),
      log: Logger([buffer], tag: 'registry'),
    );

    expect((await store.load()).reminders, isEmpty);

    final record = buffer.records.single;
    expect(record.event, 'load.unreadable');
    expect(record.level, LogLevel.error);
    expect(record.error, isA<FormatException>());
  });

  testWidgets('reported and uncaught errors reach the log', (tester) async {
    final buffer = LogBuffer();
    final reported = <FlutterErrorDetails>[];
    final flutterOnError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    FlutterError.onError = reported.add;
    try {
      installErrorLogging(Logger([buffer], tag: 'error'));
      reportRescheduleError(StateError('run'), StackTrace.current, 'testing');
      final handled = PlatformDispatcher.instance.onError!(
        ArgumentError('async'),
        StackTrace.current,
      );
      expect(handled, isFalse, reason: 'the platform still reports it too');
    } finally {
      FlutterError.onError = flutterOnError;
      PlatformDispatcher.instance.onError = platformOnError;
    }

    expect(reported, hasLength(1), reason: 'the previous handler still runs');
    final [flutter, uncaught] = buffer.records;
    expect(flutter.event, 'flutter');
    expect(flutter.error, isA<StateError>());
    expect(flutter.fields['context'], 'while testing');
    expect(uncaught.event, 'uncaught');
    expect(uncaught.error, isA<ArgumentError>());
  });
}

/// Lets [failAfter] schedule calls through, then rejects the next one.
class _FailingGateway extends FakeNotificationGateway {
  _FailingGateway({required this.failAfter});
  int failAfter;

  @override
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  }) async {
    if (failAfter-- == 0) throw StateError('the OS rejected the schedule');
    return super.schedule(reminder, title: title, body: body);
  }
}
