import '../core/launch_recovery.dart';
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

  /// Whether this process has handed the whole desired set to the OS yet.
  bool _handedOver = false;

  int get skippedCount => _coordinator.skippedCount;

  /// Route a trigger through the debounced/serialized/de-duplicated entry point.
  Future<void> request(RescheduleTrigger trigger) =>
      _coordinator.request(trigger);

  /// Run the launch-time reschedule, and return the recovery reason found in
  /// the persisted state (OS-cleared, cold start, periodic top-up, or a DST
  /// shift while idle), or null if nothing looked wrong.
  ///
  /// It reschedules either way: a process's first run hands the whole schedule
  /// back to the OS (see [_perform]), and that must not wait for the next
  /// resume or edit. With no recovery reason the run is an ordinary
  /// [RescheduleTrigger.appResume].
  Future<RescheduleTrigger?> recoverOnLaunch() async {
    final registry = await _store.load();
    final pending = await _gateway.pendingIds();
    final trigger = _recovery.decide(
      registry: registry,
      pendingIds: pending,
      now: clock.now().toUtc(),
    );
    await request(trigger ?? RescheduleTrigger.appResume);
    return trigger;
  }

  Future<void> _perform(RescheduleTrigger trigger) async {
    final registry = await _store.load();
    final trips = await _loadTrips();

    final result = await _engine.reconcile(
      registry: registry,
      trips: trips,
      now: clock.now().toUtc(),
      trigger: trigger,
      lastKnownIana: registry.lastZoneId,
    );

    // Scheduling only the diff assumes the registry mirrors what the OS has
    // pending. Two cases break that. On [RescheduleTrigger.osCleared] the OS
    // reported its pending set gone. And on a process's first run nobody can
    // tell: Android's pending list is the plugin's own record, so alarms lost
    // to a force-stop still read as pending, and Android 14 and older never
    // re-arm them. In both, hand over the whole desired set instead. Ids are
    // deterministic, so that overwrites what survived rather than duplicating
    // it. What to cancel still comes from the diff.
    final handOver = !_handedOver || trigger == RescheduleTrigger.osCleared;
    final toSchedule =
        handOver ? result.registry.reminders : result.plan.toSchedule;

    for (final id in result.plan.toCancel) {
      await _gateway.cancel(id);
    }
    for (final reminder in toSchedule) {
      await _gateway.schedule(reminder,
          title: _title(reminder), body: _body(reminder));
    }
    await _store.save(result.registry);
    _handedOver = true;
  }

  static String _defaultTitle(ScheduledReminder _) => 'Trip reminder';
  static String _defaultBody(ScheduledReminder _) =>
      'Your daily reminder for the trip.';
}
