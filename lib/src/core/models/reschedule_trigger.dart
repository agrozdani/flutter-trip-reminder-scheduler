/// Every reason a (re)schedule might happen. The point of enumerating them is
/// that they all funnel through one debounced, serialized entry point
/// ([RescheduleCoordinator](../reschedule_coordinator.dart)) rather than each
/// call site poking the scheduler directly.
enum RescheduleTrigger {
  /// First schedule for a freshly created trip.
  initialSchedule,

  /// The user edited a trip (time, dates, destination).
  userEdit,

  /// The device's timezone setting changed.
  timezoneChanged,

  /// A live-location signal changed which zone "today" should use.
  locationChanged,

  /// App launched after being closed for a while (> 6h since last schedule).
  coldStart,

  /// A daylight-saving transition was detected.
  dstTransition,

  /// The OS cleared pending notifications (e.g. on reboot) and we noticed.
  osCleared,

  /// Periodic top-up so the schedule never drifts too stale.
  periodicRebalance,

  /// App returned to the foreground.
  appResume;

  /// High-priority triggers bypass the short de-duplication window so a user
  /// edit or a detected DST shift is never dropped just because another
  /// reschedule ran moments ago.
  bool get isHighPriority => _highPriority.contains(this);

  static const Set<RescheduleTrigger> _highPriority = {
    RescheduleTrigger.userEdit,
    RescheduleTrigger.locationChanged,
    RescheduleTrigger.dstTransition,
    RescheduleTrigger.osCleared,
  };
}
