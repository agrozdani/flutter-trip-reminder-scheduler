import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/reminder_time.dart';
import '../../core/models/trip.dart';
import '../common_zones.dart';
import '../providers.dart';
import '../trip_controller.dart';

/// Defines a trip: home zone, destination country, dates, daily reminder time,
/// and optional pre/post buffer days. On save it hands a [Trip] to the
/// controller, which schedules the timezone-aware reminders.
class TripFormScreen extends ConsumerStatefulWidget {
  const TripFormScreen({super.key});

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  String _homeIana = 'America/New_York';
  String? _country;
  late DateTime _start;
  late DateTime _end;
  TimeOfDay _reminder = const TimeOfDay(hour: 9, minute: 0);
  int _preBuffer = 1;
  int _postBuffer = 1;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _start = DateTime.utc(today.year, today.month, today.day).add(const Duration(days: 7));
    _end = _start.add(const Duration(days: 5));
  }

  @override
  Widget build(BuildContext context) {
    final countries = ref.read(countryZoneMapProvider).countries;
    _country ??= countries.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Add trip')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Label('Home zone'),
          DropdownButtonFormField<String>(
            initialValue: _homeIana,
            items: [
              for (final z in kCommonZones)
                DropdownMenuItem(value: z, child: Text(z)),
            ],
            onChanged: (v) => setState(() => _homeIana = v ?? _homeIana),
          ),
          const SizedBox(height: 16),
          _Label('Destination country'),
          DropdownButtonFormField<String>(
            initialValue: _country,
            items: [
              for (final c in countries)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _country = v),
          ),
          const SizedBox(height: 8),
          _DateRow(
            label: 'Start date',
            value: _start,
            onPick: (d) => setState(() {
              _start = d;
              if (_end.isBefore(_start)) _end = _start;
            }),
          ),
          _DateRow(
            label: 'End date',
            value: _end,
            onPick: (d) => setState(() => _end = d.isBefore(_start) ? _start : d),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Daily reminder time'),
            trailing: Text(_reminder.format(context)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _reminder,
              );
              if (picked != null) setState(() => _reminder = picked);
            },
          ),
          const SizedBox(height: 8),
          _Stepper(
            label: 'Pre-trip buffer days (home zone)',
            value: _preBuffer,
            onChanged: (v) => setState(() => _preBuffer = v),
          ),
          _Stepper(
            label: 'Post-trip buffer days (home zone)',
            value: _postBuffer,
            onChanged: (v) => setState(() => _postBuffer = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save & schedule'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final trip = Trip(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      homeIana: _homeIana,
      destinationCountry: _country!,
      startDate: DateTime.utc(_start.year, _start.month, _start.day),
      endDate: DateTime.utc(_end.year, _end.month, _end.day),
      reminderTime: ReminderTime(_reminder.hour, _reminder.minute),
      preBufferDays: _preBuffer,
      postBufferDays: _postBuffer,
    );
    await ref.read(tripsControllerProvider.notifier).addTrip(trip);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip saved and reminders scheduled')),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value, required this.onPick});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text('${value.year}-${_two(value.month)}-${_two(value.day)}'),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 2),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < 14 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
