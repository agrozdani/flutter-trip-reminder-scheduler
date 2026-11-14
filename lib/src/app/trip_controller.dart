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
final tripsControllerProvider =
    AsyncNotifierProvider<TripsController, List<Trip>>(TripsController.new);

class TripsController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => ref.read(tripStoreProvider).load();

  // Both mutations wait for the stored trips first: starting from an empty
  // list while the load is still in flight would save over them.
  Future<void> addTrip(Trip trip) async {
    final current = await future;
    await _commit([...current, trip]);
  }

  Future<void> removeTrip(String id) async {
    final current = await future;
    await _commit(current.where((t) => t.id != id).toList());
  }

  Future<void> _commit(List<Trip> trips) async {
    await ref.read(tripStoreProvider).save(trips);
    state = AsyncData(trips);
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
