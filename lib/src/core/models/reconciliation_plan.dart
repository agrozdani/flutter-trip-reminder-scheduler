import 'scheduled_reminder.dart';

/// The output of reconciling a desired schedule against the persisted one.
///
/// Splitting the diff into three explicit buckets is what makes idempotence
/// testable: re-running with identical inputs yields an empty [toSchedule] and
/// empty [toCancel] (everything lands in [unchanged]), so nothing is
/// re-scheduled and nothing is duplicated.
class ReconciliationPlan {
  const ReconciliationPlan({
    this.toSchedule = const [],
    this.toCancel = const [],
    this.unchanged = const [],
  });

  /// New or changed reminders that must be (re)scheduled with the OS.
  final List<ScheduledReminder> toSchedule;

  /// Ids that are stale and must be cancelled.
  final List<int> toCancel;

  /// Ids already scheduled with an identical fire instant; left untouched.
  final List<int> unchanged;

  /// True when there is nothing to do — the converged steady state.
  bool get isNoop => toSchedule.isEmpty && toCancel.isEmpty;

  @override
  String toString() => 'ReconciliationPlan(schedule:${toSchedule.length}, '
      'cancel:${toCancel.length}, unchanged:${unchanged.length})';
}
