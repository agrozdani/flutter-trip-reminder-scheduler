import '../models/reminder_registry.dart';

/// Persists the [ReminderRegistry] across launches.
///
/// The production app used an encrypted Hive box; here it is plain
/// `shared_preferences` (JSON) in the app and an in-memory map in tests. The
/// core only cares that it can load the last persisted registry and save a new
/// one — the storage mechanism is the adapter's business.
abstract interface class RegistryStore {
  /// Loads the persisted registry, or [ReminderRegistry.empty] if none exists.
  Future<ReminderRegistry> load();

  /// Persists [registry] as the new source of truth.
  Future<void> save(ReminderRegistry registry);
}
