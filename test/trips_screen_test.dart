import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/app.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/platform/overridable_device_timezone_source.dart';
import 'package:trip_reminder_scheduler/src/platform/prefs_trip_store.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // The app over fakes with one stored trip, launch run done, then Delete
  // tapped and the outcome settled.
  Future<void> deleteTheTrip(
    WidgetTester tester, {
    required PrefsTripStore Function(SharedPreferences) store,
    required FakeNotificationGateway gateway,
  }) async {
    final trip = Trip(
      id: 'trip',
      homeIana: 'UTC',
      destinationCountry: 'United Kingdom',
      startDate: DateTime.utc(2030, 6, 12),
      endDate: DateTime.utc(2030, 6, 12),
      reminderTime: const ReminderTime(9, 0),
    );
    SharedPreferences.setMockInitialValues({
      'trips_v1': jsonEncode([trip.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tripStoreProvider.overrideWithValue(store(prefs)),
          gatewayProvider.overrideWithValue(gateway),
          registryStoreProvider.overrideWithValue(InMemoryRegistryStore()),
          deviceTimezoneSourceProvider.overrideWithValue(
            OverridableDeviceTimezoneSource(FakeDeviceTimezoneSource('UTC')),
          ),
        ],
        child: const TripReminderApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1)); // the launch run

    final onError = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = onError;
    }
  }

  testWidgets('a delete that could not be saved says the trip is kept', (
    tester,
  ) async {
    await deleteTheTrip(
      tester,
      store: _UnwritableTripStore.new,
      gateway: FakeNotificationGateway(),
    );

    expect(find.byTooltip('Delete'), findsOneWidget, reason: 'still listed');
    expect(find.text('The trip could not be deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a delete whose reschedule fails says the trip is gone', (
    tester,
  ) async {
    await deleteTheTrip(
      tester,
      store: PrefsTripStore.new,
      gateway: _CancelRejectingGateway(),
    );

    expect(find.byTooltip('Delete'), findsNothing);
    expect(
      find.text('Trip deleted, but the schedule could not be updated'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}

/// A trip store whose writes fail, as a platform write can.
class _UnwritableTripStore extends PrefsTripStore {
  _UnwritableTripStore(super.prefs);

  @override
  Future<void> save(List<Trip> trips) async =>
      throw PlatformException(code: 'write_failed');
}

/// A gateway whose OS rejects every cancel.
class _CancelRejectingGateway extends FakeNotificationGateway {
  @override
  Future<void> cancel(int id) async =>
      throw PlatformException(code: 'cancel_failed');
}
