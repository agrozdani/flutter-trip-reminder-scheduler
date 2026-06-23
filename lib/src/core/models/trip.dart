import 'reminder_time.dart';

/// A user-defined trip with a single daily reminder that should "travel" with
/// them: fire in the home zone before departure and after return, and in the
/// destination zone while away.
///
/// Only the calendar-date part of [startDate] / [endDate] is meaningful; any
/// time component is ignored by the engine.
class Trip {
  const Trip({
    required this.id,
    required this.homeIana,
    required this.destinationCountry,
    required this.startDate,
    required this.endDate,
    required this.reminderTime,
    this.preBufferDays = 0,
    this.postBufferDays = 0,
  });

  /// Stable id; used as the seed for deterministic notification ids.
  final String id;

  /// IANA zone the user calls home (e.g. `America/New_York`).
  final String homeIana;

  /// Destination as a country name, resolved to a zone via the country map so
  /// the resolver's provenance/confidence is exercised.
  final String destinationCountry;

  /// First day at the destination (date part only).
  final DateTime startDate;

  /// Last day at the destination (date part only).
  final DateTime endDate;

  /// Wall-clock time the daily reminder should fire.
  final ReminderTime reminderTime;

  /// Extra reminder days before [startDate] (spent in the home zone).
  final int preBufferDays;

  /// Extra reminder days after [endDate] (spent in the home zone).
  final int postBufferDays;

  Trip copyWith({
    String? id,
    String? homeIana,
    String? destinationCountry,
    DateTime? startDate,
    DateTime? endDate,
    ReminderTime? reminderTime,
    int? preBufferDays,
    int? postBufferDays,
  }) {
    return Trip(
      id: id ?? this.id,
      homeIana: homeIana ?? this.homeIana,
      destinationCountry: destinationCountry ?? this.destinationCountry,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      reminderTime: reminderTime ?? this.reminderTime,
      preBufferDays: preBufferDays ?? this.preBufferDays,
      postBufferDays: postBufferDays ?? this.postBufferDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'homeIana': homeIana,
        'destinationCountry': destinationCountry,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'reminderTime': reminderTime.formatted,
        'preBufferDays': preBufferDays,
        'postBufferDays': postBufferDays,
      };

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        homeIana: json['homeIana'] as String,
        destinationCountry: json['destinationCountry'] as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        reminderTime: ReminderTime.parse(json['reminderTime'] as String),
        preBufferDays: (json['preBufferDays'] as num?)?.toInt() ?? 0,
        postBufferDays: (json['postBufferDays'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is Trip &&
      other.id == id &&
      other.homeIana == homeIana &&
      other.destinationCountry == destinationCountry &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.reminderTime == reminderTime &&
      other.preBufferDays == preBufferDays &&
      other.postBufferDays == postBufferDays;

  @override
  int get hashCode => Object.hash(id, homeIana, destinationCountry, startDate,
      endDate, reminderTime, preBufferDays, postBufferDays);

  @override
  String toString() =>
      'Trip($id, $homeIana -> $destinationCountry, ${reminderTime.formatted})';
}
