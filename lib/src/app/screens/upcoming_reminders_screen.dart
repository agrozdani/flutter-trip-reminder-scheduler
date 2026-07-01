import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/models/resolved_zone.dart';
import '../../core/models/scheduled_reminder.dart';
import '../providers.dart';

/// Mirrors the persisted registry: every scheduled reminder with its resolved
/// fire time, IANA zone, resolution source, and confidence. This is the window
/// into what the engine actually decided.
///
/// A reminder whose instant has passed stays listed — dimmed and badged
/// "fired" — until the next reconcile prunes it from the registry. The badge
/// is derived at render time (see [firedReminderIdsProvider]); the registry
/// itself is never mutated for display.
class UpcomingRemindersScreen extends ConsumerWidget {
  const UpcomingRemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingRemindersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming reminders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(upcomingRemindersProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (registry) {
          final reminders = registry.sortedByFireTime;
          if (reminders.isEmpty) {
            return const _Empty();
          }
          return Column(
            children: [
              _Header(
                count: registry.count,
                lastZone: registry.lastZoneId,
                lastAt: registry.lastScheduleAtUtc,
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: reminders.length,
                  itemBuilder: (_, i) => _ReminderTile(reminders[i]),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, this.lastZone, this.lastAt});

  final int count;
  final String? lastZone;
  final DateTime? lastAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count scheduled',
                    style: Theme.of(context).textTheme.titleMedium),
                if (lastZone != null)
                  Text('Dominant zone: $lastZone',
                      style: Theme.of(context).textTheme.bodySmall),
                if (lastAt != null)
                  Text('Last scheduled: ${_fmtUtc(lastAt!)} UTC',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text('cap 64', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile(this.reminder);

  final ScheduledReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "Fired" is derived display state — the instant has passed; whether the
    // OS actually delivered it is unknowable, so the badge says "fired", not
    // "delivered". Selecting just this id means only the card crossing the
    // boundary rebuilds when the provider's timer fires.
    final fired = ref.watch(
      firedReminderIdsProvider.select((ids) => ids.contains(reminder.id)),
    );
    final local = tz.TZDateTime.from(reminder.fireInstantUtc, _location(reminder.iana));
    return Opacity(
      opacity: fired ? 0.55 : 1.0,
      child: ListTile(
        leading: CircleAvatar(child: Text('${reminder.dayIndex}')),
        title: Text('${_fmtLocal(local)}  ·  ${reminder.iana}'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (fired) const _Chip('fired', Colors.grey),
              _Chip(reminder.source.name, _sourceColor(reminder.source)),
              _Chip(reminder.confidence.name, _confidenceColor(reminder.confidence)),
              _Chip('trip ${reminder.tripId}', Colors.grey),
              _Chip('${_fmtUtc(reminder.fireInstantUtc)}Z', Colors.blueGrey),
            ],
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No reminders scheduled yet.\nAdd a trip to see its timezone-aware schedule here.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

tz.Location _location(String iana) {
  try {
    return tz.getLocation(iana);
  } catch (_) {
    return tz.UTC;
  }
}

Color _sourceColor(ZoneSource source) => switch (source) {
      ZoneSource.userChosen => Colors.indigo,
      ZoneSource.liveLocation => Colors.green,
      ZoneSource.deviceTimezone => Colors.blue,
      ZoneSource.countryHeuristic => Colors.deepPurple,
      ZoneSource.lastKnown => Colors.teal,
      ZoneSource.localeFallback => Colors.orange,
      ZoneSource.utcFallback => Colors.red,
    };

Color _confidenceColor(ZoneConfidence confidence) => switch (confidence) {
      ZoneConfidence.high => Colors.green,
      ZoneConfidence.medium => Colors.blue,
      ZoneConfidence.low => Colors.orange,
      ZoneConfidence.fallback => Colors.red,
    };

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtLocal(tz.TZDateTime dt) =>
    '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';

String _fmtUtc(DateTime dt) {
  final u = dt.toUtc();
  return '${u.year}-${_two(u.month)}-${_two(u.day)} ${_two(u.hour)}:${_two(u.minute)}';
}
