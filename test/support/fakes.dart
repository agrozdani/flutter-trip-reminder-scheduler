import 'package:trip_reminder_scheduler/src/core/models/reminder_registry.dart';
import 'package:trip_reminder_scheduler/src/core/models/scheduled_reminder.dart';
import 'package:trip_reminder_scheduler/src/core/ports/country_zone_map.dart';
import 'package:trip_reminder_scheduler/src/core/ports/device_timezone_source.dart';
import 'package:trip_reminder_scheduler/src/core/ports/location_zone_source.dart';
import 'package:trip_reminder_scheduler/src/core/ports/notification_gateway.dart';
import 'package:trip_reminder_scheduler/src/core/ports/registry_store.dart';

/// Device timezone you can set to any IANA id (or null for "unavailable").
class FakeDeviceTimezoneSource implements DeviceTimezoneSource {
  FakeDeviceTimezoneSource([this.iana]);
  String? iana;
  @override
  Future<String?> currentIana() async => iana;
}

/// Live-location signal you can switch on (a zone) or off (null).
class FakeLocationZoneSource implements LocationZoneSource {
  FakeLocationZoneSource([this.iana]);
  String? iana;
  @override
  Future<String?> currentIana() async => iana;
}

/// A small, deterministic country→zone table for tests. Includes multi-zone
/// countries (United States, Australia) so the confidence-downgrade path runs.
class FakeCountryZoneMap implements CountryZoneMap {
  FakeCountryZoneMap([Map<String, List<String>>? data]) : _data = data ?? _default;

  final Map<String, List<String>> _data;

  static const Map<String, List<String>> _default = {
    'United Kingdom': ['Europe/London'],
    'Nigeria': ['Africa/Lagos'],
    'Japan': ['Asia/Tokyo'],
    'India': ['Asia/Kolkata'],
    'Germany': ['Europe/Berlin'],
    'United States': [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
    ],
    'Australia': ['Australia/Sydney', 'Australia/Perth'],
  };

  @override
  String? ianaFor(String country) => _data[country]?.first;

  @override
  bool hasMultiple(String country) => (_data[country]?.length ?? 0) > 1;

  @override
  List<String> get countries => _data.keys.toList();
}

/// Records what was scheduled/cancelled and what the OS reports as pending.
/// Set [simulateOsCleared] to keep [pendingIds] empty even after scheduling, to
/// reproduce the OS wiping pending notifications on reboot.
class FakeNotificationGateway implements NotificationGateway {
  final List<ScheduledReminder> scheduled = [];
  final List<int> cancelled = [];
  bool cancelledAll = false;
  bool simulateOsCleared = false;
  final List<int> _pending = [];

  @override
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  }) async {
    scheduled.add(reminder);
    if (!simulateOsCleared && !_pending.contains(reminder.id)) {
      _pending.add(reminder.id);
    }
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    _pending.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
    _pending.clear();
  }

  @override
  Future<List<int>> pendingIds() async => List.of(_pending);

  /// Force the pending set (e.g. to simulate the OS clearing everything).
  void setPending(List<int> ids) {
    _pending
      ..clear()
      ..addAll(ids);
  }
}

/// In-memory [RegistryStore] for tests.
class InMemoryRegistryStore implements RegistryStore {
  InMemoryRegistryStore([ReminderRegistry? initial])
      : _registry = initial ?? ReminderRegistry.empty;

  ReminderRegistry _registry;

  @override
  Future<ReminderRegistry> load() async => _registry;

  @override
  Future<void> save(ReminderRegistry registry) async => _registry = registry;
}
