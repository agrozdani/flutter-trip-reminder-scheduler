import 'reminder_time.dart';
import 'reschedule_trigger.dart';
import 'resolved_zone.dart';

/// One concrete scheduled reminder: an absolute instant plus the full
/// provenance of how it was computed.
///
/// The source of truth is [fireInstantUtc] — an absolute UTC instant, never a
/// wall-clock time. Everything else ([iana], [source], [confidence], ...) is
/// metadata that makes the schedule observable and recoverable. This is the
/// sanitized analogue of the production app's persisted notification metadata.
class ScheduledReminder {
  ScheduledReminder({
    required this.id,
    required this.fireInstantUtc,
    required this.iana,
    required this.source,
    required this.confidence,
    required this.trigger,
    required this.tripId,
    required this.dayIndex,
    required this.wallClock,
    required this.scheduledAtUtc,
  })  : assert(fireInstantUtc.isUtc, 'fireInstantUtc must be UTC'),
        assert(scheduledAtUtc.isUtc, 'scheduledAtUtc must be UTC');

  /// Deterministic notification id (stable across runs for the same input).
  final int id;

  /// The absolute instant the reminder fires. The persisted truth.
  final DateTime fireInstantUtc;

  /// IANA zone used to compute [fireInstantUtc].
  final String iana;

  /// How [iana] was resolved.
  final ZoneSource source;

  /// Confidence in [iana].
  final ZoneConfidence confidence;

  /// What triggered the schedule that produced this reminder.
  final RescheduleTrigger trigger;

  /// Owning trip id.
  final String tripId;

  /// Day offset within the trip's reminder window (0-based).
  final int dayIndex;

  /// The wall-clock time the user asked for (for display/forensics).
  final ReminderTime wallClock;

  /// When this reminder was scheduled.
  final DateTime scheduledAtUtc;

  ScheduledReminder copyWith({
    int? id,
    DateTime? fireInstantUtc,
    String? iana,
    ZoneSource? source,
    ZoneConfidence? confidence,
    RescheduleTrigger? trigger,
    String? tripId,
    int? dayIndex,
    ReminderTime? wallClock,
    DateTime? scheduledAtUtc,
  }) {
    return ScheduledReminder(
      id: id ?? this.id,
      fireInstantUtc: fireInstantUtc ?? this.fireInstantUtc,
      iana: iana ?? this.iana,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      trigger: trigger ?? this.trigger,
      tripId: tripId ?? this.tripId,
      dayIndex: dayIndex ?? this.dayIndex,
      wallClock: wallClock ?? this.wallClock,
      scheduledAtUtc: scheduledAtUtc ?? this.scheduledAtUtc,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fireInstantUtc': fireInstantUtc.toIso8601String(),
        'iana': iana,
        'source': source.name,
        'confidence': confidence.name,
        'trigger': trigger.name,
        'tripId': tripId,
        'dayIndex': dayIndex,
        'wallClock': wallClock.formatted,
        'scheduledAtUtc': scheduledAtUtc.toIso8601String(),
      };

  factory ScheduledReminder.fromJson(Map<String, dynamic> json) {
    return ScheduledReminder(
      id: (json['id'] as num).toInt(),
      fireInstantUtc: DateTime.parse(json['fireInstantUtc'] as String).toUtc(),
      iana: json['iana'] as String,
      source: _byName(ZoneSource.values, json['source'] as String),
      confidence: _byName(ZoneConfidence.values, json['confidence'] as String),
      trigger: _byName(RescheduleTrigger.values, json['trigger'] as String),
      tripId: json['tripId'] as String,
      dayIndex: (json['dayIndex'] as num).toInt(),
      wallClock: ReminderTime.parse(json['wallClock'] as String),
      scheduledAtUtc:
          DateTime.parse(json['scheduledAtUtc'] as String).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.id == id &&
      other.fireInstantUtc == fireInstantUtc &&
      other.iana == iana &&
      other.source == source &&
      other.confidence == confidence &&
      other.trigger == trigger &&
      other.tripId == tripId &&
      other.dayIndex == dayIndex &&
      other.wallClock == wallClock &&
      other.scheduledAtUtc == scheduledAtUtc;

  @override
  int get hashCode => Object.hash(id, fireInstantUtc, iana, source, confidence,
      trigger, tripId, dayIndex, wallClock, scheduledAtUtc);

  @override
  String toString() => 'ScheduledReminder(id:$id, fire:$fireInstantUtc, '
      '$iana, ${source.name}/${confidence.name}, trip:$tripId#$dayIndex)';
}

T _byName<T extends Enum>(List<T> values, String name) =>
    values.firstWhere((v) => v.name == name);
