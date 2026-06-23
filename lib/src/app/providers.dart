import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/reminder_registry.dart';
import '../core/ports/country_zone_map.dart';
import '../core/ports/notification_gateway.dart';
import '../core/ports/registry_store.dart';
import '../core/schedule_engine.dart';
import '../core/timezone_resolver.dart';
import '../platform/flutter_notification_gateway.dart';
import '../platform/flutter_timezone_device_source.dart';
import '../platform/manual_location_zone_source.dart';
import '../platform/overridable_device_timezone_source.dart';
import '../platform/prefs_registry_store.dart';
import '../platform/prefs_trip_store.dart';
import '../platform/small_country_zone_map.dart';
import 'reminder_scheduler.dart';

/// Async singletons created in `main()` and injected via [ProviderScope]
/// overrides — they fail loudly if that wiring is forgotten.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);
final notificationPluginProvider = Provider<FlutterLocalNotificationsPlugin>(
  (ref) => throw UnimplementedError('Override notificationPluginProvider in main()'),
);

// --- Ports (adapters wrapping the platform plugins) ----------------------------

/// Concrete type exposed so the simulate screen can set the live zone.
final locationZoneSourceProvider = Provider<ManualLocationZoneSource>(
  (ref) => ManualLocationZoneSource(),
);

/// Concrete type exposed so the simulate screen can set the device override.
final deviceTimezoneSourceProvider = Provider<OverridableDeviceTimezoneSource>(
  (ref) => OverridableDeviceTimezoneSource(const FlutterTimezoneDeviceSource()),
);

final countryZoneMapProvider = Provider<CountryZoneMap>(
  (ref) => const SmallCountryZoneMap(),
);

final gatewayProvider = Provider<NotificationGateway>(
  (ref) => FlutterNotificationGateway(ref.watch(notificationPluginProvider)),
);

final registryStoreProvider = Provider<RegistryStore>(
  (ref) => PrefsRegistryStore(ref.watch(sharedPreferencesProvider)),
);

final tripStoreProvider = Provider<PrefsTripStore>(
  (ref) => PrefsTripStore(ref.watch(sharedPreferencesProvider)),
);

// --- Pure core, wired to the ports ---------------------------------------------

final resolverProvider = Provider<TimezoneResolver>(
  (ref) => TimezoneResolver(
    deviceSource: ref.watch(deviceTimezoneSourceProvider),
    locationSource: ref.watch(locationZoneSourceProvider),
    countryMap: ref.watch(countryZoneMapProvider),
  ),
);

final engineProvider = Provider<ScheduleEngine>(
  (ref) => ScheduleEngine(resolver: ref.watch(resolverProvider)),
);

/// The single orchestrator. Must be a singleton so its debounce/serialize state
/// is shared across every trigger; [Provider] caches it per container.
final schedulerProvider = Provider<ReminderScheduler>((ref) {
  final tripStore = ref.watch(tripStoreProvider);
  return ReminderScheduler(
    engine: ref.watch(engineProvider),
    gateway: ref.watch(gatewayProvider),
    registryStore: ref.watch(registryStoreProvider),
    loadTrips: tripStore.load,
  );
});

/// The persisted schedule, surfaced to the "upcoming reminders" screen.
/// Invalidate it after a reschedule to refresh the view.
final upcomingRemindersProvider = FutureProvider<ReminderRegistry>(
  (ref) => ref.watch(registryStoreProvider).load(),
);
