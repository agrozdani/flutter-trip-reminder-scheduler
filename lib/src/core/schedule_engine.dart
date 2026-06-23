import 'package:timezone/timezone.dart' as tz;

import 'models/reconciliation_plan.dart';
import 'models/reminder_registry.dart';
import 'models/reschedule_trigger.dart';
import 'models/resolved_zone.dart';
import 'models/scheduled_reminder.dart';
import 'models/trip.dart';
import 'timezone_resolver.dart';
import 'wall_clock.dart';

/// The pure heart of the system: given trips and "now", decide the exact set of
/// absolute instants that should be scheduled, and diff that against what is
/// already persisted.
///
/// It performs no I/O and imports no Flutter. The caller applies the resulting
/// [ReconciliationPlan] to the OS and persists the returned registry.
class ScheduleEngine {
  ScheduleEngine({
    required this.resolver,
    this.maxScheduled = 64,
    this.microOffset = const Duration(seconds: 5),
  });

  final TimezoneResolver resolver;

  /// Hard cap on pending notifications. iOS keeps at most ~64 pending local
  /// notifications, so we never schedule more than this many, soonest first.
  final int maxScheduled;

  /// How far apart to nudge reminders that would otherwise fire in the same
  /// minute, so none is silently dropped by the OS as a duplicate.
  final Duration microOffset;

  /// Build the desired schedule for [trips] and reconcile it against
  /// [registry]. Returns the diff to apply plus the registry to persist.
  Future<ReconciliationResult> reconcile({
    required ReminderRegistry registry,
    required List<Trip> trips,
    required DateTime now,
    required RescheduleTrigger trigger,
    String? lastKnownIana,
    String? localeCountry,
  }) async {
    final nowUtc = now.toUtc();

    final desired = <ScheduledReminder>[];
    for (final trip in trips) {
      desired.addAll(await candidatesFor(
        trip,
        now: nowUtc,
        trigger: trigger,
        lastKnownIana: lastKnownIana,
        localeCountry: localeCountry,
      ));
    }

    // Deterministic order: by instant, then a stable tie-break so micro-offset
    // assignment and the cap are reproducible run to run.
    desired.sort((a, b) {
      final byInstant = a.fireInstantUtc.compareTo(b.fireInstantUtc);
      if (byInstant != 0) return byInstant;
      final byTrip = a.tripId.compareTo(b.tripId);
      if (byTrip != 0) return byTrip;
      return a.dayIndex.compareTo(b.dayIndex);
    });

    final spaced = _applyMicroOffsets(desired);
    final capped = spaced.take(maxScheduled).toList();

    final plan = _diff(registry, capped);
    final newRegistry = registry.copyWith(
      reminders: capped,
      lastZoneId: capped.isNotEmpty ? capped.first.iana : registry.lastZoneId,
      lastScheduleAtUtc: nowUtc,
    );
    return ReconciliationResult(plan: plan, registry: newRegistry);
  }

  /// The travel-aware core: one reminder per day across the trip's window,
  /// each day choosing its zone by context.
  ///
  /// - **today** + a high-confidence live location → that live zone (overrides
  ///   any phase);
  /// - **destination days** (between start and end) → the destination zone;
  /// - **home days** (the pre/post buffer) → the home zone.
  Future<List<ScheduledReminder>> candidatesFor(
    Trip trip, {
    required DateTime now,
    required RescheduleTrigger trigger,
    String? lastKnownIana,
    String? localeCountry,
  }) async {
    final nowUtc = now.toUtc();

    // Resolve the three candidate zones once per trip.
    final home = await resolver.resolveHomeZone(trip.homeIana);
    final destination = await resolver.resolveForDestination(trip.destinationCountry);
    final todayZone = await resolver.resolveForCurrentZone(
      lastKnownIana: lastKnownIana,
      localeCountry: localeCountry,
    );

    final start = _dateOnly(trip.startDate);
    final end = _dateOnly(trip.endDate);
    final anchor = start.subtract(Duration(days: trip.preBufferDays));
    final lastDay = end.add(Duration(days: trip.postBufferDays));
    final total = lastDay.difference(anchor).inDays;

    // "Today" is defined in the home zone — the context the user thinks about
    // their trip dates in.
    final homeNow = tz.TZDateTime.from(nowUtc, home.location);
    final todayDate = DateTime.utc(homeNow.year, homeNow.month, homeNow.day);

    final out = <ScheduledReminder>[];
    for (var i = 0; i <= total; i++) {
      final date = anchor.add(Duration(days: i));
      final isDestinationDay =
          i >= trip.preBufferDays && i <= total - trip.postBufferDays;
      final isToday = date == todayDate;

      final ResolvedZone zone;
      if (isToday && todayZone.source == ZoneSource.liveLocation) {
        zone = todayZone;
      } else if (isDestinationDay) {
        zone = destination;
      } else {
        zone = home;
      }

      final fire = WallClock.toInstant(
        zone.location,
        date.year,
        date.month,
        date.day,
        trip.reminderTime.hour,
        trip.reminderTime.minute,
      );
      final fireUtc = fire.toUtc();

      // Never schedule something already in the past.
      if (!fireUtc.isAfter(nowUtc)) continue;

      out.add(ScheduledReminder(
        id: deterministicId(trip.id, i),
        fireInstantUtc: fireUtc,
        iana: zone.iana,
        source: zone.source,
        confidence: zone.confidence,
        trigger: trigger,
        tripId: trip.id,
        dayIndex: i,
        wallClock: trip.reminderTime,
        scheduledAtUtc: nowUtc,
      ));
    }
    return out;
  }

  /// Stable, content-derived id so the same (trip, day) always maps to the same
  /// notification id across runs — the basis for idempotent rescheduling.
  /// Masked to a positive 31-bit int, which is safe for platform ids.
  ///
  /// The whole `'$tripId#$dayIndex'` key is hashed as one string. Folding
  /// [dayIndex] in afterwards with the same `* 31` multiplier used between
  /// characters let it share a range with the trip-id hash, so two trips whose
  /// hashes differed by `k` collided whenever their day indices differed by
  /// `31 * k`; the `#`-separated composite key keeps distinct pairs distinct.
  static int deterministicId(String tripId, int dayIndex) {
    final key = '$tripId#$dayIndex';
    var hash = 17;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  /// Push reminders sharing a minute apart by [microOffset] each, in order, so
  /// the OS does not coalesce or drop them.
  List<ScheduledReminder> _applyMicroOffsets(List<ScheduledReminder> sorted) {
    final perMinute = <int, int>{};
    final out = <ScheduledReminder>[];
    for (final reminder in sorted) {
      final minute =
          reminder.fireInstantUtc.millisecondsSinceEpoch ~/ 60000;
      final seen = perMinute[minute] ?? 0;
      perMinute[minute] = seen + 1;
      if (seen == 0) {
        out.add(reminder);
      } else {
        out.add(reminder.copyWith(
          fireInstantUtc: reminder.fireInstantUtc.add(microOffset * seen),
        ));
      }
    }
    return out;
  }

  /// Diff desired against persisted: schedule new/changed ids, cancel stale
  /// ids, leave identical ones untouched.
  ReconciliationPlan _diff(
    ReminderRegistry registry,
    List<ScheduledReminder> desired,
  ) {
    final existing = {for (final r in registry.reminders) r.id: r};
    final desiredIds = desired.map((r) => r.id).toSet();

    final toSchedule = <ScheduledReminder>[];
    final unchanged = <int>[];
    for (final d in desired) {
      final prev = existing[d.id];
      if (prev == null || prev.fireInstantUtc != d.fireInstantUtc) {
        toSchedule.add(d);
      } else {
        unchanged.add(d.id);
      }
    }
    final toCancel =
        registry.ids.where((id) => !desiredIds.contains(id)).toList();

    return ReconciliationPlan(
      toSchedule: toSchedule,
      toCancel: toCancel,
      unchanged: unchanged,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}

/// The output of [ScheduleEngine.reconcile]: what to change, and the registry
/// to persist once the change is applied.
class ReconciliationResult {
  ReconciliationResult({required this.plan, required this.registry});

  final ReconciliationPlan plan;
  final ReminderRegistry registry;
}
