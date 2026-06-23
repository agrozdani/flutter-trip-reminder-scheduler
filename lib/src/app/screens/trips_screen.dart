import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/trip.dart';
import '../trip_controller.dart';
import 'trip_form_screen.dart';

/// Lists the user's trips and lets them add or delete one. Every change flows
/// through [TripsController], which persists and reschedules.
class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trips')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const TripFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add trip'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (trips) {
          if (trips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No trips yet.\nTap "Add trip" to schedule timezone-aware reminders.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: trips.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _TripTile(trips[i]),
          );
        },
      ),
    );
  }
}

class _TripTile extends ConsumerWidget {
  const _TripTile(this.trip);

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buffers = (trip.preBufferDays > 0 || trip.postBufferDays > 0)
        ? '  ·  +${trip.preBufferDays}/${trip.postBufferDays} buffer'
        : '';
    return ListTile(
      leading: const Icon(Icons.flight_takeoff),
      title: Text('${trip.destinationCountry}  ·  ${trip.reminderTime.formatted}'),
      subtitle: Text(
        'Home ${trip.homeIana}\n'
        '${_date(trip.startDate)} → ${_date(trip.endDate)}$buffers',
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () =>
            ref.read(tripsControllerProvider.notifier).removeTrip(trip.id),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
