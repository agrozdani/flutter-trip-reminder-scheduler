import 'package:timezone/timezone.dart' as tz;

import 'models/reminder_registry.dart';
import 'models/reschedule_trigger.dart';

/// Decides whether — and why — to reschedule when the app launches.
///
/// Local notifications are fragile: the OS drops pending ones on reboot, the
/// app can sit closed across a DST change, and a long-dormant queue drains as
/// reminders fire. This pure function inspects the persisted registry against
/// what the OS still has pending and returns the trigger to run, or null when
/// the schedule is still fresh and intact.
///
/// Note: unlike the source app — whose cold-start check (≥6h) shadowed its
/// periodic check (≥20d), making the latter unreachable at launch — the
/// thresholds here are tested most-specific first, so every branch is live.
class LaunchRecovery {
  const LaunchRecovery({
    this.coldStartAfter = const Duration(hours: 6),
    this.periodicAfter = const Duration(days: 20),
  });

  /// Treat a launch this long after the last schedule as a cold start.
  final Duration coldStartAfter;

  /// Top the queue up if it has been this long since the last schedule.
  final Duration periodicAfter;

  RescheduleTrigger? decide({
    required ReminderRegistry registry,
    required List<int> pendingIds,
    required DateTime now,
  }) {
    final nowUtc = now.toUtc();

    // We believe we have a schedule, but the OS has nothing pending: it was
    // cleared (typically a reboot). Highest priority.
    if (registry.reminders.isNotEmpty && pendingIds.isEmpty) {
      return RescheduleTrigger.osCleared;
    }

    final last = registry.lastScheduleAtUtc?.toUtc();
    if (last == null) {
      return RescheduleTrigger.coldStart;
    }

    final elapsed = nowUtc.difference(last);
    if (elapsed >= periodicAfter) {
      return RescheduleTrigger.periodicRebalance;
    }
    if (elapsed >= coldStartAfter) {
      return RescheduleTrigger.coldStart;
    }
    if (_dstShifted(registry.lastZoneId, last, nowUtc)) {
      return RescheduleTrigger.dstTransition;
    }
    return null;
  }

  /// True if [iana]'s UTC offset differs now from what it was at [then] — i.e.
  /// a DST transition happened in between while the app was idle.
  bool _dstShifted(String? iana, DateTime then, DateTime now) {
    if (iana == null) return false;
    try {
      final loc = tz.getLocation(iana);
      final offsetThen = tz.TZDateTime.from(then, loc).timeZoneOffset;
      final offsetNow = tz.TZDateTime.from(now, loc).timeZoneOffset;
      return offsetThen != offsetNow;
    } catch (_) {
      return false;
    }
  }
}
