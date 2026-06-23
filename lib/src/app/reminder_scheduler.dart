import '../core/launch_recovery.dart';
import '../core/models/reminder_registry.dart';
import '../core/models/reschedule_trigger.dart';
import '../core/models/scheduled_reminder.dart';
import '../core/models/trip.dart';
import '../core/ports/clock.dart';
import '../core/ports/notification_gateway.dart';
import '../core/ports/registry_store.dart';
import '../core/reschedule_coordinator.dart';
import '../core/schedule_engine.dart';

/// Supplies the current set of trips when a reschedule runs.
typedef TripsLoader = Future<List<Trip>> Function();

/// The application service that ties the pure core to the real ports.
///
/// Every reschedule trigger goes through [request] → the [RescheduleCoordinator]
/// → [_perform], which loads state, runs the [ScheduleEngine], applies the diff
/// to the [NotificationGateway], and persists the new registry. It imports no
/// Flutter, so it can be driven end-to-end in a unit test with fakes.
class ReminderScheduler {
  ReminderScheduler({
    required this._engine,
    required this._gateway,
    required RegistryStore registryStore,
    required this._loadTrips,
    this._recovery = const LaunchRecovery(),
    String Function(ScheduledReminder reminder)? title,
    String Function(ScheduledReminder reminder)? body,
  })  : _store = registryStore,
        _title = title ?? _defaultTitle,
        _body = body ?? _defaultBody {
    _coordinator = RescheduleCoordinator(onReschedule: _perform);
  }

  final ScheduleEngine _engine;
  final NotificationGateway _gateway;
  final RegistryStore _store;
  final TripsLoader _loadTrips;
  final LaunchRecovery _recovery;
  final String Function(ScheduledReminder) _title;
  final String Function(ScheduledReminder) _body;

  late final RescheduleCoordinator _coordinator;

  int get skippedCount => _coordinator.skippedCount;

  /// Route a trigger through the debounced/serialized/de-duplicated entry point.
  Future<void> request(RescheduleTrigger trigger) =>
      _coordinator.request(trigger);

  /// Inspect the persisted state at launch and reschedule if recovery is needed
  /// (OS-cleared, cold start, periodic top-up, or a DST shift while idle).
  Future<RescheduleTrigger?> recoverOnLaunch() async {
    final registry = await _store.load();
    final pending = await _gateway.pendingIds();
    final trigger = _recovery.decide(
      registry: registry,
      pendingIds: pending,
      now: clock.now().toUtc(),
    );
    if (trigger != null) {
      await request(trigger);
    }
    return trigger;
  }

  Future<void> _perform(RescheduleTrigger trigger) async {
    final registry = await _store.load();
    final trips = await _loadTrips();

    // The fire-time diff assumes the registry reflects what the OS actually has
    // pending. That holds for every trigger except [osCleared], where the OS
    // wiped its pending set out from under us (typically a reboot). There we
    // reconcile against an empty baseline so the whole desired set is treated
    // as new, and clear any stragglers up front.
    final osCleared = trigger == RescheduleTrigger.osCleared;
    final baseline = osCleared ? ReminderRegistry.empty : registry;

    final result = await _engine.reconcile(
      registry: baseline,
      trips: trips,
      now: clock.now().toUtc(),
      trigger: trigger,
      lastKnownIana: registry.lastZoneId,
    );

    if (osCleared) {
      await _gateway.cancelAll();
    } else {
      for (final id in result.plan.toCancel) {
        await _gateway.cancel(id);
      }
    }
    for (final reminder in result.plan.toSchedule) {
      await _gateway.schedule(reminder,
          title: _title(reminder), body: _body(reminder));
    }
    await _store.save(result.registry);
  }

  static String _defaultTitle(ScheduledReminder _) => 'Trip reminder';
  static String _defaultBody(ScheduledReminder _) =>
      'Your daily reminder for the trip.';
}
