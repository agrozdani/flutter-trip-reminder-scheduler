import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:trip_reminder_scheduler/src/core/wall_clock.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('spring-forward gap — the wall time does not exist', () {
    test('New York 2024-03-10 02:30 shifts forward instead of vanishing', () {
      final loc = tz.getLocation('America/New_York');
      final result = WallClock.toInstant(loc, 2024, 3, 10, 2, 30);
      // 02:00–02:59 are skipped as clocks jump EST(-5) -> EDT(-4). The instant
      // is 07:30 UTC, which renders as 03:30 EDT — a real, sensible time.
      expect(result.toUtc(), DateTime.utc(2024, 3, 10, 7, 30));
      expect(result.hour, 3);
    });
  });

  group('fall-back overlap — the wall time happens twice', () {
    test('New York 2024-11-03 01:30 resolves to the standard-time occurrence',
        () {
      final loc = tz.getLocation('America/New_York');
      final result = WallClock.toInstant(loc, 2024, 11, 3, 1, 30);
      // 01:30 occurs at 05:30 UTC (EDT) then again at 06:30 UTC (EST). We pick
      // the later, standard-time occurrence.
      expect(result.toUtc(), DateTime.utc(2024, 11, 3, 6, 30));
      expect(result.timeZoneOffset, const Duration(hours: -5),
          reason: 'EST, the standard-time side');
    });
  });

  group('direction-agnostic — southern hemisphere transitions', () {
    test('Sydney spring-forward 2024-10-06 02:30 shifts forward', () {
      final loc = tz.getLocation('Australia/Sydney');
      final result = WallClock.toInstant(loc, 2024, 10, 6, 2, 30);
      // AEST(+10) -> AEDT(+11); 02:00–02:59 do not exist.
      expect(result.toUtc(), DateTime.utc(2024, 10, 5, 16, 30));
      expect(result.hour, 3);
    });

    test('Sydney fall-back 2024-04-07 02:30 takes the standard (AEST) side',
        () {
      final loc = tz.getLocation('Australia/Sydney');
      final result = WallClock.toInstant(loc, 2024, 4, 7, 2, 30);
      // AEDT(+11) -> AEST(+10); the later occurrence is AEST.
      expect(result.toUtc(), DateTime.utc(2024, 4, 6, 16, 30));
      expect(result.timeZoneOffset, const Duration(hours: 10));
    });
  });

  group('sub-hour transition — Lord Howe Island shifts by 30 minutes', () {
    // 2024-04-07 fall-back: AEDT(+11) -> AEST(+10:30); clocks go 02:00 -> 01:30,
    // so only 01:30–01:59 are ambiguous, and 01:00–01:29 happen exactly once.
    test('a unique time just before the 30-min overlap is not shifted', () {
      final loc = tz.getLocation('Australia/Lord_Howe');
      final result = WallClock.toInstant(loc, 2024, 4, 7, 1, 0);
      // 01:00 exists once at +11 -> 2024-04-06 14:00 UTC. A naive one-hour DST
      // probe used to misread this as ambiguous and push it 30 min late.
      expect(result.toUtc(), DateTime.utc(2024, 4, 6, 14, 0));
      expect(result.timeZoneOffset, const Duration(hours: 11));
    });

    test('a genuinely ambiguous time takes the later (standard) occurrence', () {
      final loc = tz.getLocation('Australia/Lord_Howe');
      final result = WallClock.toInstant(loc, 2024, 4, 7, 1, 45);
      // 01:45 occurs at 14:45 UTC (+11) then 15:15 UTC (+10:30); pick the later.
      expect(result.toUtc(), DateTime.utc(2024, 4, 6, 15, 15));
      expect(result.timeZoneOffset, const Duration(hours: 10, minutes: 30));
    });
  });

  test('an unambiguous time is returned unchanged', () {
    final loc = tz.getLocation('America/New_York');
    final result = WallClock.toInstant(loc, 2024, 6, 15, 9, 0);
    expect(result.toUtc(), DateTime.utc(2024, 6, 15, 13, 0), reason: 'EDT -4');
    expect(result.hour, 9);
  });
}
