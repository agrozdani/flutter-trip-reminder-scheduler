import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:trip_reminder_scheduler/src/core/wall_clock.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  DateTime instant(String iana, int y, int mo, int d, int h, int mi) =>
      WallClock.toInstant(tz.getLocation(iana), y, mo, d, h, mi).toUtc();

  test('New York 09:00 in winter is 14:00 UTC (EST, -5)', () {
    expect(instant('America/New_York', 2024, 1, 15, 9, 0),
        DateTime.utc(2024, 1, 15, 14, 0));
  });

  test('London 09:00 in winter is 09:00 UTC (GMT)', () {
    expect(instant('Europe/London', 2024, 1, 15, 9, 0),
        DateTime.utc(2024, 1, 15, 9, 0));
  });

  test('Tokyo 09:00 is 00:00 UTC (JST, +9, no DST)', () {
    expect(instant('Asia/Tokyo', 2024, 1, 15, 9, 0),
        DateTime.utc(2024, 1, 15, 0, 0));
  });

  test('half-hour zone: Kolkata 09:00 is 03:30 UTC (+5:30)', () {
    expect(instant('Asia/Kolkata', 2024, 1, 15, 9, 0),
        DateTime.utc(2024, 1, 15, 3, 30));
  });

  test('the same wall clock is a different instant in a far-away home zone', () {
    final ny = instant('America/New_York', 2024, 1, 15, 9, 0);
    final lagos = instant('Africa/Lagos', 2024, 1, 15, 9, 0);
    expect(lagos, DateTime.utc(2024, 1, 15, 8, 0), reason: 'WAT +1');
    expect(ny.difference(lagos), const Duration(hours: 6));
  });

  test('date-line: Apia 09:00 maps to the previous UTC day', () {
    final loc = tz.getLocation('Pacific/Apia');
    final result = WallClock.toInstant(loc, 2024, 1, 15, 9, 0);
    // Apia sits far east of UTC (+13/+14), so a morning there is the previous
    // day in UTC. Asserting the day avoids hard-coding the exact offset.
    expect(result.day, 15);
    expect(result.hour, 9);
    expect(result.toUtc().day, 14);
  });
}
