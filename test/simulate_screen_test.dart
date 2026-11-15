import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/app/app.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/platform/overridable_device_timezone_source.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('the zone pickers fit a narrow screen with large text', (
    tester,
  ) async {
    // 320 dp wide, as on an iPhone SE (1st generation), with text at 200%.
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          gatewayProvider.overrideWithValue(FakeNotificationGateway()),
          registryStoreProvider.overrideWithValue(InMemoryRegistryStore()),
          deviceTimezoneSourceProvider.overrideWithValue(
            OverridableDeviceTimezoneSource(FakeDeviceTimezoneSource('UTC')),
          ),
        ],
        child: const TripReminderApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1)); // the launch run
    await tester.tap(find.text('Simulate'));
    await tester.pumpAndSettle();

    // Scroll to the last card, so both cards' pickers are laid out.
    await tester.scrollUntilVisible(
      find.text('Force a DST-transition reschedule'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
