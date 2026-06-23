/// A wall-clock time of day with no date and no zone attached.
///
/// This is deliberately *not* a `DateTime`: a reminder time like "09:00" is a
/// wall-clock intention, and the same "09:00" means a different absolute
/// instant in every timezone. Keeping it zone-free until the
/// [WallClock](../wall_clock.dart) resolves it against a concrete zone and date
/// is the core discipline of the whole project.
class ReminderTime {
  const ReminderTime(this.hour, this.minute)
      : assert(hour >= 0 && hour <= 23),
        assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  /// Parses `"HH:mm"` or `"HH:mm:ss"`. Extra fields are ignored.
  ///
  /// Validates the ranges explicitly and throws a [FormatException] on bad
  /// input — the constructor's assertions are debug-only, so without this a
  /// corrupt persisted `"24:00"` would survive into a release build.
  factory ReminderTime.parse(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      throw FormatException('Expected HH:mm, got "$value"');
    }
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw FormatException('Time out of range: "$value"');
    }
    return ReminderTime(hour, minute);
  }

  /// `"HH:mm"`, always two digits each.
  String get formatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => formatted;
}
