import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/app.dart';
import 'package:trip_reminder_scheduler/src/app/home_shell.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/platform/overridable_device_timezone_source.dart';
import 'package:trip_reminder_scheduler/src/platform/prefs_trip_store.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('a double tap on Save adds the trip once and pops once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        gatewayProvider.overrideWithValue(FakeNotificationGateway()),
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
    final save = find.text('Save & schedule');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();

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
}
