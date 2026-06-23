import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/reschedule_coordinator.dart';

void main() {
  test('a burst of requests coalesces into a single run', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

      c.request(RescheduleTrigger.coldStart);
      c.request(RescheduleTrigger.periodicRebalance);
      c.request(RescheduleTrigger.appResume);
      async.elapse(const Duration(milliseconds: 300));

      expect(runs, hasLength(1));
    });
  });

  test('the highest-priority trigger from a burst is the one that runs', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

      c.request(RescheduleTrigger.periodicRebalance); // low
      c.request(RescheduleTrigger.userEdit); // high
      c.request(RescheduleTrigger.appResume); // low
      async.elapse(const Duration(milliseconds: 300));

      expect(runs, [RescheduleTrigger.userEdit]);
    });
  });

  test('runs are serialized — they never overlap', () {
    fakeAsync((async) {
      var active = 0;
      var maxActive = 0;
      final c = RescheduleCoordinator(
        dedupWindow: Duration.zero, // disable dedup for this test
        onReschedule: (t) async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(seconds: 1));
          active--;
        },
      );

      c.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));
      async.elapse(const Duration(seconds: 1)); // first run finishes
      c.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 300));
      async.elapse(const Duration(seconds: 1));

      expect(maxActive, 1);
    });
  });

  test('a low-priority repeat within the dedup window is skipped', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

      c.request(RescheduleTrigger.coldStart);
      async.elapse(const Duration(milliseconds: 300));
      expect(runs, hasLength(1));

      c.request(RescheduleTrigger.periodicRebalance); // within 5s
      async.elapse(const Duration(milliseconds: 300));

      expect(runs, hasLength(1), reason: 'deduped');
      expect(c.skippedCount, 1);
    });
  });

  test('a high-priority trigger bypasses the dedup window', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

      c.request(RescheduleTrigger.coldStart);
      async.elapse(const Duration(milliseconds: 300));
      expect(runs, hasLength(1));

      c.request(RescheduleTrigger.userEdit); // high priority, within 5s
      async.elapse(const Duration(milliseconds: 300));

      expect(runs, hasLength(2), reason: 'high priority is never dropped');
      expect(runs.last, RescheduleTrigger.userEdit);
    });
  });

  test('a failed run surfaces its error but does not poison the coordinator',
      () {
    fakeAsync((async) {
      var calls = 0;
      var failNext = true;
      Object? surfaced;
      final c = RescheduleCoordinator(
        dedupWindow: Duration.zero,
        onReschedule: (t) async {
          calls++;
          if (failNext) {
            failNext = false;
            throw StateError('transient failure');
          }
        },
      );

      // First run throws; the failure must reach the caller...
      c.request(RescheduleTrigger.coldStart).catchError((Object e) {
        surfaced = e;
      });
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1);
      expect(surfaced, isA<StateError>(), reason: 'error surfaced to caller');

      // ...but a later request must still run (no permanent poisoning).
      c.request(RescheduleTrigger.periodicRebalance);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 2, reason: 'coordinator recovered after the failure');
    });
  });

  test('a fresh run is allowed once the dedup window has elapsed', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

      c.request(RescheduleTrigger.coldStart);
      async.elapse(const Duration(milliseconds: 300));
      async.elapse(const Duration(seconds: 6)); // past the 5s window

      c.request(RescheduleTrigger.periodicRebalance);
      async.elapse(const Duration(milliseconds: 300));

      expect(runs, hasLength(2));
    });
  });
}
