import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_reminder_scheduler/src/app/providers.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
import 'package:trip_reminder_scheduler/src/core/models/reminder_time.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/models/resolved_zone.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';

import 'support/fakes.dart';

void main() {
  ScheduledReminder reminder(int id, DateTime fireUtc) => ScheduledReminder(
        id: id,
        fireInstantUtc: fireUtc,
        iana: 'Europe/London',
        source: ZoneSource.countryHeuristic,
        confidence: ZoneConfidence.medium,
        trigger: RescheduleTrigger.initialSchedule,
        tripId: 't1',
        dayIndex: id,
        wallClock: const ReminderTime(9, 0),
        scheduledAtUtc: DateTime.utc(2024, 1, 1),
      );

  test('fired ids flip at each fire instant via one armed timer, no polling',
      () {
    fakeAsync((async) {
      final registry = ReminderRegistry(
        reminders: [
          reminder(1, DateTime.utc(2024, 1, 1, 1, 0)),
          reminder(2, DateTime.utc(2024, 1, 1, 2, 0)),
        ],
        lastScheduleAtUtc: DateTime.utc(2024, 1, 1),
      );
      final container = ProviderContainer(overrides: [
        registryStoreProvider
            .overrideWithValue(InMemoryRegistryStore(registry)),
      ]);
      // Keep the autoDispose provider alive, as the screen's tiles would.
      final sub = container.listen(firedReminderIdsProvider, (_, _) {});

      async.flushMicrotasks(); // let the FutureProvider load the registry
      expect(sub.read(), isEmpty, reason: 'nothing has fired yet');

      // Just past the first fire instant (+1s timer pad): only id 1 flips.
      async.elapse(const Duration(hours: 1, seconds: 2));
      expect(sub.read(), {1});

      // Past the second: the re-armed timer catches it too.
      async.elapse(const Duration(hours: 1));
      expect(sub.read(), {1, 2});

      container.dispose();
    }, initialTime: DateTime.utc(2024, 1, 1));
  });
}
