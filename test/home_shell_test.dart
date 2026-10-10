import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/app.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/app/reminder_scheduler.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
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

  late InMemoryRegistryStore store;
  var trips = const <Trip>[];
  var failRuns = false;
  setUp(() {
    trips = const [];
    failRuns = false;
  });

  // The app over an in-memory store, with a scheduler that reconciles [trips]
  // and whose runs throw while [failRuns] is set.
  Future<void> pumpApp(WidgetTester tester, ReminderRegistry initial) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = InMemoryRegistryStore(initial);
    final scheduler = ReminderScheduler(
      engine: ScheduleEngine(
        resolver: TimezoneResolver(
          deviceSource: FakeDeviceTimezoneSource('UTC'),
          locationSource: FakeLocationZoneSource(),
          countryMap: FakeCountryZoneMap(),
        ),
      ),
      gateway: FakeNotificationGateway(),
      registryStore: store,
      loadTrips: () async {
        if (failRuns) throw StateError('reschedule failed');
        return trips;
      },
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        registryStoreProvider.overrideWithValue(store),
        schedulerProvider.overrideWithValue(scheduler),
      ],
      child: const TripReminderApp(),
    ));
  }

  // Collects what FlutterError reports while [body] runs, restoring the
  // handler before returning so a later failing expect is reported normally.
  Future<List<FlutterErrorDetails>> reportedDuring(
    Future<void> Function() body,
  ) async {
    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await body();
    } finally {
      FlutterError.onError = onError;
    }
    return reported;
  }

  ReminderRegistry oneReminder(DateTime nowUtc) => ReminderRegistry(
        reminders: [
          ScheduledReminder(
            id: 1,
            fireInstantUtc: nowUtc.add(const Duration(hours: 1)),
            iana: 'UTC',
            source: ZoneSource.userChosen,
            confidence: ZoneConfidence.high,
            trigger: RescheduleTrigger.userEdit,
            tripId: 't1',
            dayIndex: 0,
            wallClock: const ReminderTime(9, 0),
            scheduledAtUtc: nowUtc,
          ),
        ],
        lastScheduleAtUtc: nowUtc,
      );

  // The app stays on the Trips tab; the Upcoming tab is mounted offstage.
  Finder upcoming(String text) => find.textContaining(text, skipOffstage: false);

  testWidgets('a failed launch recovery is reported and the view still refreshes',
      (tester) async {
    // Never scheduled, so launch recovery requests a cold-start run.
    failRuns = true;
    await pumpApp(tester, ReminderRegistry.empty);
    await tester.pump();
    expect(upcoming('No reminders scheduled yet'), findsOneWidget);

    // Change what a refresh would show, then let the debounced run fail.
    await store.save(oneReminder(clock.now().toUtc()));
    final reported = await reportedDuring(() async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });

    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.context.toString(), contains('launch-time recovery'));
    expect(upcoming('1 scheduled'), findsOneWidget,
        reason: 'the view refreshes even though the run failed');

    await tester.pumpWidget(const SizedBox()); // dispose the provider graph
  });

  testWidgets('a failed resume reschedule is reported and the view still refreshes',
      (tester) async {
    // Just scheduled with nothing expected pending: launch recovery is a no-op.
    await pumpApp(tester, ReminderRegistry(lastScheduleAtUtc: clock.now().toUtc()));
    await tester.pump(const Duration(seconds: 1));
    expect(upcoming('No reminders scheduled yet'), findsOneWidget);

    failRuns = true;
    final reported = await reportedDuring(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // Only now change what a refresh would show, so a refresh that happened
      // before the run can't show it.
      await store.save(oneReminder(clock.now().toUtc()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });

    expect(reported.single.exception, isA<StateError>());
    expect(reported.single.context.toString(), contains('app resume'));
    expect(upcoming('1 scheduled'), findsOneWidget,
        reason: 'the view refreshes even though the run failed');

    await tester.pumpWidget(const SizedBox()); // dispose the provider graph
  });

  testWidgets('a resume reschedule refreshes the view once it has run',
      (tester) async {
    await pumpApp(tester, ReminderRegistry(lastScheduleAtUtc: clock.now().toUtc()));
    await tester.pump(const Duration(seconds: 1));
    expect(upcoming('No reminders scheduled yet'), findsOneWidget);

    // A trip for tomorrow, so the resume run itself saves one reminder.
    final now = clock.now().toUtc();
    final tomorrow = DateTime.utc(now.year, now.month, now.day + 1);
    trips = [
      Trip(
        id: 't1',
        homeIana: 'UTC',
        destinationCountry: 'United Kingdom',
        startDate: tomorrow,
        endDate: tomorrow,
        reminderTime: const ReminderTime(9, 0),
      ),
    ];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(upcoming('1 scheduled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose the provider graph
  });
}
