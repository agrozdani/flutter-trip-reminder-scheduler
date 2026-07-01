import 'dart:async';

import 'models/reschedule_trigger.dart';
import 'ports/clock.dart';

/// Called to actually perform a reschedule for a given trigger.
typedef RescheduleCallback = Future<void> Function(RescheduleTrigger trigger);

/// The single safe entry point every reschedule trigger funnels through.
///
/// Many unrelated events want to reschedule (a user edit, a timezone change, a
/// cold start, ...). Letting each call the engine directly invites duplicate,
/// overlapping, and racing schedules. This coordinator imposes three
/// disciplines:
///
/// - **debounce** — a burst of requests within [debounce] collapses into one;
/// - **serialize** — runs never overlap; each awaits the previous;
/// - **de-duplicate** — a low-priority repeat within [dedupWindow] of the last
///   run is skipped, while high-priority triggers (a user edit, a live-location
///   change, a detected DST shift, an OS-cleared schedule) always run.
///
/// It reads "now" through `package:clock`, so tests drive it deterministically
/// with `fakeAsync`.
class RescheduleCoordinator {
  RescheduleCoordinator({
    required this._onReschedule,
    this.debounce = const Duration(milliseconds: 300),
    this.dedupWindow = const Duration(seconds: 5),
  });

  final RescheduleCallback _onReschedule;
  final Duration debounce;
  final Duration dedupWindow;

  RescheduleTrigger? _pending;
  bool _queued = false;
  Future<void> _chain = Future<void>.value();
  Future<void> _outcome = Future<void>.value();
  bool _running = false;
  DateTime? _lastRunAt;
  int _skippedCount = 0;

  /// How many low-priority requests have been de-duplicated away. Useful for
  /// observability and tests.
  int get skippedCount => _skippedCount;

  /// Request a reschedule. Returns a future that completes when the coalesced
  /// run that covers this request has finished.
  Future<void> request(RescheduleTrigger trigger) {
    _pending = _moreImportantOf(_pending, trigger);
    if (_queued) return _outcome;

    _queued = true;
    final outcome = Completer<void>();
    _outcome = outcome.future;
    // The internal [_chain] exists only to serialize runs, so it must never
    // complete with an error: if it did, the next `.then` would skip its
    // callback and `_queued` would stay stuck true, permanently disabling every
    // future reschedule. We therefore catch inside the chain and forward any
    // failure to the caller's [outcome] instead, leaving the chain healthy.
    _chain = _chain.then((_) async {
      await Future<void>.delayed(debounce);
      final effective = _pending ?? trigger;
      // Reset before running so requests arriving mid-run queue a fresh pass.
      _queued = false;
      _pending = null;
      try {
        await _run(effective);
        outcome.complete();
      } catch (error, stackTrace) {
        outcome.completeError(error, stackTrace);
      }
    });
    return outcome.future;
  }

  Future<void> _run(RescheduleTrigger trigger) async {
    if (_running) return;

    final now = clock.now();
    final last = _lastRunAt;
    final withinWindow = last != null && now.difference(last) < dedupWindow;
    if (withinWindow && !trigger.isHighPriority) {
      _skippedCount++;
      return;
    }

    _running = true;
    try {
      await _onReschedule(trigger);
      _lastRunAt = clock.now();
    } finally {
      _running = false;
    }
  }

  /// Keeps a high-priority trigger once one has been seen during a debounce
  /// window, so it is never overwritten by a later low-priority request.
  RescheduleTrigger _moreImportantOf(RescheduleTrigger? current, RescheduleTrigger next) {
    if (current == null) return next;
    if (next.isHighPriority && !current.isHighPriority) return next;
    return current;
  }
}
