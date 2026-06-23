import 'package:timezone/timezone.dart' as tz;

/// Converts a zone-free wall-clock time on a calendar date into an absolute
/// instant in a specific zone — correctly handling the two ways daylight-saving
/// time makes that conversion ambiguous or impossible.
///
/// A naive `DateTime(y, m, d, h, mi)` silently uses the host's own offset and
/// has no concept of a zone's DST rules. `WallClock.toInstant` resolves against
/// the real zone history in `package:timezone`, so "09:00 in Europe/London on
/// 2024-03-31" maps to the right UTC instant even though 01:00–01:59 that night
/// does not exist.
abstract final class WallClock {
  /// Resolves the wall-clock `[hour]:[minute]` on `[year]-[month]-[day]` in
  /// [location] to an absolute instant.
  ///
  /// **Spring-forward gap** — when clocks jump forward, an hour of wall-clock
  /// time never happens. The `timezone` package normalizes such a time forward;
  /// we keep that, so a reminder set for a non-existent 02:30 fires at the
  /// shifted 03:30 rather than silently vanishing.
  ///
  /// **Fall-back overlap** — when clocks go back, an hour of wall-clock time
  /// happens twice. We deliberately pick the *second*, standard-time occurrence
  /// for consistency, so an ambiguous time always resolves the same way.
  static tz.TZDateTime toInstant(
    tz.Location location,
    int year,
    int month,
    int day,
    int hour,
    int minute,
  ) {
    final local = tz.TZDateTime(location, year, month, day, hour, minute);

    // Spring-forward gap: the constructor rolled the wall time forward, so what
    // we got back no longer matches what we asked for. Accept the shift.
    if (local.hour != hour || local.minute != minute) {
      return local;
    }

    // Fall-back overlap: when clocks go back, this wall time can happen twice.
    // Build the candidate for the *later*, standard-time occurrence — read the
    // wall clock as if it were UTC, then subtract the post-transition offset —
    // and accept it only if it genuinely round-trips back to the requested wall
    // time and lands after `local`. That verification is what keeps this correct
    // for sub-hour transitions (e.g. Lord Howe's 30-minute shift), where a fixed
    // one-hour probe would misread the half hour just before the overlap as
    // ambiguous. Building from DateTime.utc also keeps the result independent of
    // the host device's own offset.
    final offsetAfter = local.add(const Duration(hours: 1)).timeZoneOffset;
    if (offsetAfter < local.timeZoneOffset) {
      final wallAsUtcMs =
          DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch;
      final candidate = tz.TZDateTime.fromMillisecondsSinceEpoch(
        location,
        wallAsUtcMs - offsetAfter.inMilliseconds,
      );
      if (candidate.isAfter(local) &&
          candidate.hour == hour &&
          candidate.minute == minute) {
        return candidate;
      }
    }

    return local;
  }
}
