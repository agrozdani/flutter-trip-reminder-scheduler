import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/reschedule_trigger.dart';
import '../core/models/trip.dart';
import 'providers.dart';

/// Holds the user's trips and keeps the schedule in sync.
///
/// Every mutation persists the trips, then routes a [RescheduleTrigger.userEdit]
/// through the scheduler and refreshes the upcoming view. The widgets stay dumb:
/// they render [state] and call [addTrip] / [removeTrip].
///
/// A mutation's future fails if its reschedule does. By then the trips are
/// already persisted and in [state], and the next successful reschedule brings
/// the schedule back in line with them.
///
/// A failed load is not retried: stored trips that can't be read won't become
/// readable, and while a retry is pending every mutation waits on [future].
final tripsControllerProvider = AsyncNotifierProvider<TripsController, List<Trip>>(
  TripsController.new,
  retry: (_, _) => null,
);

class TripsController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => ref.read(tripStoreProvider).load();

  Future<void> addTrip(Trip trip) => _mutate((current) => [...current, trip]);

  Future<void> removeTrip(String id) =>
      _mutate((current) => current.where((t) => t.id != id).toList());

  /// The end of the queue of saves, which never completes with an error.
  Future<void> _saves = Future<void>.value();

  /// Applies [change] to the trips, persists them, then reschedules.
  ///
  /// Saves run one at a time, each starting from the trips the previous one
  /// left: two that overlapped would start from the same list, and the later
  /// save would bring back a trip the earlier one removed. The first also waits
  /// for the stored trips, rather than starting from an empty list while the
  /// load is still in flight and saving over them.
  Future<void> _mutate(List<Trip> Function(List<Trip> current) change) async {
    final saved = _saves.then((_) async {
      final trips = change(await future);
      await ref.read(tripStoreProvider).save(trips);
      state = AsyncData(trips);
    });
    _saves = saved.catchError((Object _) {});
    await saved;
    await reschedule(RescheduleTrigger.userEdit);
  }

  /// Run the scheduler for [trigger] and refresh the upcoming-reminders view
  /// once it has finished, whether or not it succeeded.
  Future<void> reschedule(RescheduleTrigger trigger) async {
    try {
      await ref.read(schedulerProvider).request(trigger);
    } finally {
      ref.invalidate(upcomingRemindersProvider);
    }
  }
}
