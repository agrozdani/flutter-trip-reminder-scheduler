import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/core/reschedule_coordinator.dart';

void main() {
  test('a burst of requests coalesces into a single run', () {
    fakeAsync((async) {
      final runs = <RescheduleTrigger>[];
      final c = RescheduleCoordinator(
        dedupWindow: Duration.zero, // so dedup can't mask a missing debounce
        onReschedule: (t) async => runs.add(t),
      );

      // Spread across the 300ms window, then drain: only one run may happen.
      c.request(RescheduleTrigger.coldStart);
      async.elapse(const Duration(milliseconds: 100));
      c.request(RescheduleTrigger.periodicRebalance);
      async.elapse(const Duration(milliseconds: 100));
      c.request(RescheduleTrigger.appResume);
      async.elapse(const Duration(seconds: 5));

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

  test('an OS-cleared resync is never coalesced into another trigger', () {
    // osCleared needs a full resync, so it must win whether it arrives before
    // or after another high-priority trigger.
    for (final burst in const [
      [RescheduleTrigger.locationChanged, RescheduleTrigger.osCleared],
      [RescheduleTrigger.osCleared, RescheduleTrigger.userEdit],
    ]) {
      fakeAsync((async) {
        final runs = <RescheduleTrigger>[];
        final c = RescheduleCoordinator(onReschedule: (t) async => runs.add(t));

        for (final trigger in burst) {
          c.request(trigger);
        }
        async.elapse(const Duration(milliseconds: 300));

        expect(runs, [RescheduleTrigger.osCleared], reason: '$burst');
      });
    }
  });

  test('runs are serialized — a request arriving mid-run waits its turn', () {
    fakeAsync((async) {
      var active = 0;
      var maxActive = 0;
      var completed = 0;
      final c = RescheduleCoordinator(
        dedupWindow: Duration.zero, // disable dedup for this test
        onReschedule: (t) async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(seconds: 1));
          active--;
          completed++;
        },
      );

      c.request(RescheduleTrigger.userEdit);
      async.elapse(const Duration(milliseconds: 500)); // run 1: 300ms..1300ms
      expect(active, 1, reason: 'first run is in progress');
      c.request(RescheduleTrigger.userEdit); // arrives mid-run
      async.elapse(const Duration(seconds: 3));

      expect(maxActive, 1, reason: 'the second run never overlapped the first');
      expect(completed, 2, reason: 'the mid-run request was queued, not dropped');
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
