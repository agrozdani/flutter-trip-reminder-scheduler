import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/app.dart';
import 'package:trip_reminder_scheduler/src/app/home_shell.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/app/screens/trip_form_screen.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
import 'package:trip_reminder_scheduler/src/core/ports/notification_gateway.dart';
import 'package:trip_reminder_scheduler/src/platform/overridable_device_timezone_source.dart';
import 'package:trip_reminder_scheduler/src/platform/prefs_trip_store.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // The app over fakes, opened on the trip form with Save scrolled into view.
  Future<SharedPreferences> pumpForm(
    WidgetTester tester,
    NotificationGateway gateway, {
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        gatewayProvider.overrideWithValue(gateway),
        registryStoreProvider.overrideWithValue(InMemoryRegistryStore()),
        deviceTimezoneSourceProvider.overrideWithValue(
          OverridableDeviceTimezoneSource(FakeDeviceTimezoneSource('UTC')),
        ),
      ],
      child: const TripReminderApp(),
    ));
    await tester.pump(const Duration(seconds: 1)); // let launch recovery run

    await tester.tap(find.text('Add trip'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save & schedule'));
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('a double tap on Save adds the trip once and pops once',
      (tester) async {
    final prefs = await pumpForm(tester, FakeNotificationGateway());
    final save = find.text('Save & schedule');

    // The second tap lands while the first save is still awaiting the 300 ms
    // debounced reschedule.
    await tester.tap(save);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(save, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(await PrefsTripStore(prefs).load(), hasLength(1));
    expect(find.byType(HomeShell), findsOneWidget,
        reason: 'the form popped once, back to the home shell');

    // Dispose the provider graph so no timer outlives the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed reschedule still closes the form and says so',
      (tester) async {
    final prefs = await pumpForm(tester, _RejectingGateway());

    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.tap(find.text('Save & schedule'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = onError;
    }

    // The trip is persisted before the reschedule runs, so the form must not
    // sit there with Save disabled, inviting a second copy of the trip.
    expect(await PrefsTripStore(prefs).load(), hasLength(1));
    expect(find.byType(TripFormScreen), findsNothing);
    expect(find.textContaining('could not be scheduled'), findsOneWidget);
    expect(reported.single.exception, isA<PlatformException>());

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Back waits for a save in flight instead of racing it',
      (tester) async {
    final prefs = await pumpForm(tester, FakeNotificationGateway());

    // Back lands while the save is awaiting the debounced reschedule. Were the
    // form to start closing now, the save's own pop a moment later would take
    // the home shell with it.
    await tester.tap(find.text('Save & schedule'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(TripFormScreen), findsOneWidget,
        reason: 'Back is held until the save has finished');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(TripFormScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(await PrefsTripStore(prefs).load(), hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Back during a save that then fails still ends with the message',
      (tester) async {
    await pumpForm(
      tester,
      _RejectingGateway(after: const Duration(seconds: 2)),
    );

    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.tap(find.text('Save & schedule'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pageBack();
      // Frame by frame, so a Back that got through would finish its exit
      // transition and dispose the form well before the reschedule fails.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = onError;
    }

    expect(reported.single.exception, isA<PlatformException>());
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.textContaining('could not be scheduled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a trip added over unreadable stored trips is not saved',
      (tester) async {
    final reported = <FlutterErrorDetails>[];
    final onError = FlutterError.onError;
    FlutterError.onError = reported.add;
    late SharedPreferences prefs;
    try {
      prefs = await pumpForm(tester, FakeNotificationGateway(),
          stored: {'trips_v1': 'not json'});
      await tester.tap(find.text('Save & schedule'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = onError;
    }

    // Launch recovery and the save both report the unreadable trips.
    expect(reported, hasLength(2));
    expect(find.byType(TripFormScreen), findsOneWidget,
        reason: 'stays open, Save enabled again, nothing overwritten');
    expect(find.text('The trip could not be saved'), findsOneWidget);
    expect(prefs.getString('trips_v1'), 'not json');

    await tester.pumpWidget(const SizedBox());
  });
}

/// A gateway whose OS rejects every schedule, as Android does while the
/// exact-alarm permission is denied — optionally only [after] a delay.
class _RejectingGateway extends FakeNotificationGateway {
  _RejectingGateway({this.after = Duration.zero});

  final Duration after;

  @override
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  }) =>
      Future.delayed(
        after,
        () => throw PlatformException(code: 'exact_alarms_not_permitted'),
      );
}
