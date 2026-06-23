import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/reschedule_trigger.dart';
import '../core/models/trip.dart';
import 'providers.dart';

/// Holds the user's trips and keeps the schedule in sync.
///
/// Every mutation persists the trips, then routes a [RescheduleTrigger.userEdit]
/// through the scheduler and refreshes the upcoming view. The widgets stay dumb:
/// they render [state] and call [addTrip] / [removeTrip].
final tripsControllerProvider =
    AsyncNotifierProvider<TripsController, List<Trip>>(TripsController.new);

class TripsController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => ref.read(tripStoreProvider).load();

  Future<void> addTrip(Trip trip) async {
    final current = state.value ?? const <Trip>[];
    await _commit([...current, trip]);
  }

  Future<void> removeTrip(String id) async {
    final current = state.value ?? const <Trip>[];
    await _commit(current.where((t) => t.id != id).toList());
  }

  Future<void> _commit(List<Trip> trips) async {
    await ref.read(tripStoreProvider).save(trips);
    state = AsyncData(trips);
    await reschedule(RescheduleTrigger.userEdit);
  }

  /// Run the scheduler for [trigger] and refresh the upcoming-reminders view
  /// once it has finished.
  Future<void> reschedule(RescheduleTrigger trigger) async {
    await ref.read(schedulerProvider).request(trigger);
    ref.invalidate(upcomingRemindersProvider);
  }
}
