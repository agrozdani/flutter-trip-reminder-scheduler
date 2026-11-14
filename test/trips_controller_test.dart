import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/app/trip_controller.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/trip.dart';
import 'package:trip_reminder_scheduler/src/platform/overridable_device_timezone_source.dart';
import 'package:trip_reminder_scheduler/src/platform/prefs_trip_store.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  Trip trip(String id) => Trip(
    id: id,
    homeIana: 'UTC',
    destinationCountry: 'United Kingdom',
    startDate: DateTime.utc(2024, 6, 12),
    endDate: DateTime.utc(2024, 6, 12),
    reminderTime: const ReminderTime(9, 0),
  );

  test('a change made before the stored trips have loaded keeps them', () {
    fakeAsync((async) {
      SharedPreferences.setMockInitialValues({
        'trips_v1': jsonEncode([trip('stored').toJson()]),
      });
      late SharedPreferences prefs;
      SharedPreferences.getInstance().then((p) => prefs = p);
      async.flushMicrotasks();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          gatewayProvider.overrideWithValue(FakeNotificationGateway()),
          registryStoreProvider.overrideWithValue(InMemoryRegistryStore()),
          deviceTimezoneSourceProvider.overrideWithValue(
            OverridableDeviceTimezoneSource(FakeDeviceTimezoneSource('UTC')),
          ),
        ],
      );

      // First touch of the controller: its load is still in flight.
      container.read(tripsControllerProvider.notifier).addTrip(trip('new'));
      async.elapse(const Duration(seconds: 1));

      late List<Trip> stored;
      PrefsTripStore(prefs).load().then((t) => stored = t);
      async.flushMicrotasks();
      expect(stored.map((t) => t.id), ['stored', 'new']);

      container.dispose();
    }, initialTime: DateTime.utc(2024, 1, 1));
  });

  test('two deletes close together both stick', () {
    fakeAsync((async) {
      SharedPreferences.setMockInitialValues({
        'trips_v1': jsonEncode([
          for (final id in ['a', 'b', 'c']) trip(id).toJson(),
        ]),
      });
      late SharedPreferences prefs;
      SharedPreferences.getInstance().then((p) => prefs = p);
      async.flushMicrotasks();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tripStoreProvider.overrideWithValue(_SlowTripStore(prefs)),
          gatewayProvider.overrideWithValue(FakeNotificationGateway()),
          registryStoreProvider.overrideWithValue(InMemoryRegistryStore()),
          deviceTimezoneSourceProvider.overrideWithValue(
            OverridableDeviceTimezoneSource(FakeDeviceTimezoneSource('UTC')),
          ),
        ],
      );
      final controller = container.read(tripsControllerProvider.notifier);
      async.elapse(const Duration(seconds: 1)); // the stored trips have loaded

      // The second delete lands while the first is still being written.
      controller.removeTrip('a');
      async.elapse(const Duration(milliseconds: 20));
      controller.removeTrip('b');
      async.elapse(const Duration(seconds: 2));

      late List<Trip> stored;
      PrefsTripStore(prefs).load().then((t) => stored = t);
      async.flushMicrotasks();
      expect(stored.map((t) => t.id), ['c']);
      expect(container.read(tripsControllerProvider).value!.map((t) => t.id), [
        'c',
      ]);

      container.dispose();
    }, initialTime: DateTime.utc(2024, 1, 1));
  });
}

/// A save that takes 50 ms, as a write over the platform channel can.
class _SlowTripStore extends PrefsTripStore {
  _SlowTripStore(super.prefs);

  @override
  Future<void> save(List<Trip> trips) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await super.save(trips);
  }
}
