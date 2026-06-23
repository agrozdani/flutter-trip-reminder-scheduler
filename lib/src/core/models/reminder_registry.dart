import 'scheduled_reminder.dart';

/// The persisted record of what is currently scheduled, plus a little context
/// used for launch-time recovery decisions.
///
/// Reconciliation diffs the *desired* set against this *persisted* set, so the
/// registry is the memory that makes repeated scheduling converge instead of
/// duplicating. Sanitized analogue of the production app's registry.
class ReminderRegistry {
  const ReminderRegistry({
    this.reminders = const [],
    this.lastZoneId,
    this.lastScheduleAtUtc,
    this.schemaVersion = 1,
  });

  /// Everything currently believed to be scheduled with the OS.
  final List<ScheduledReminder> reminders;

  /// The dominant zone at the last schedule, used to detect DST shifts.
  final String? lastZoneId;

  /// When the last full schedule ran, used for cold-start / periodic checks.
  final DateTime? lastScheduleAtUtc;

  /// For forward-compatible persistence migrations.
  final int schemaVersion;

  static const ReminderRegistry empty = ReminderRegistry();

  int get count => reminders.length;

  List<int> get ids => reminders.map((r) => r.id).toList(growable: false);

  List<ScheduledReminder> get sortedByFireTime =>
      [...reminders]..sort((a, b) => a.fireInstantUtc.compareTo(b.fireInstantUtc));

  ReminderRegistry copyWith({
    List<ScheduledReminder>? reminders,
    String? lastZoneId,
    DateTime? lastScheduleAtUtc,
    int? schemaVersion,
  }) {
    return ReminderRegistry(
      reminders: reminders ?? this.reminders,
      lastZoneId: lastZoneId ?? this.lastZoneId,
      lastScheduleAtUtc: lastScheduleAtUtc ?? this.lastScheduleAtUtc,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'lastZoneId': lastZoneId,
        'lastScheduleAtUtc': lastScheduleAtUtc?.toIso8601String(),
        'reminders': reminders.map((r) => r.toJson()).toList(),
      };

  factory ReminderRegistry.fromJson(Map<String, dynamic> json) {
    final rawReminders = (json['reminders'] as List<dynamic>? ?? const []);
    return ReminderRegistry(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      lastZoneId: json['lastZoneId'] as String?,
      lastScheduleAtUtc: json['lastScheduleAtUtc'] == null
          ? null
          : DateTime.parse(json['lastScheduleAtUtc'] as String).toUtc(),
      reminders: rawReminders
          .map((e) => ScheduledReminder.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  String toString() =>
      'ReminderRegistry(count:$count, lastZone:$lastZoneId, lastAt:$lastScheduleAtUtc)';
}
