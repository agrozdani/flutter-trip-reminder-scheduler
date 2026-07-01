import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/reschedule_trigger.dart';
import '../common_zones.dart';
import '../providers.dart';
import '../trip_controller.dart';

/// The debug seam, surfaced as UI. Because a simulator can't change real GPS or
/// the device clock, these controls drive the injectable sources directly and
/// route a reschedule through the same path the real triggers use.
class SimulateScreen extends ConsumerStatefulWidget {
  const SimulateScreen({super.key});

  @override
  ConsumerState<SimulateScreen> createState() => _SimulateScreenState();
}

class _SimulateScreenState extends ConsumerState<SimulateScreen> {
  String _location = 'Europe/London';
  String _device = 'Europe/Paris';

  Future<void> _reschedule(RescheduleTrigger trigger, String message) async {
    await ref.read(tripsControllerProvider.notifier).reschedule(trigger);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final locationSource = ref.read(locationZoneSourceProvider);
    final deviceSource = ref.read(deviceTimezoneSourceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Simulate')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            title: 'Simulate "I\'m in zone X today"',
            description:
                'Sets a high-confidence live-location signal. Only today\'s '
                'reminder switches to this zone; other days keep their home or '
                'destination zone.',
            current: locationSource.zone == null
                ? 'No live signal'
                : 'Live zone: ${locationSource.zone}',
            content: _ZonePicker(
              value: _location,
              onChanged: (v) => setState(() => _location = v),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  locationSource.zone = _location;
                  _reschedule(RescheduleTrigger.locationChanged,
                      'Live location set to $_location');
                },
                child: const Text('Apply'),
              ),
              OutlinedButton(
                onPressed: () {
                  locationSource.zone = null;
                  _reschedule(RescheduleTrigger.locationChanged,
                      'Live location cleared');
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          _Card(
            title: 'Simulate a device timezone change',
            description:
                'Overrides the zone the resolver\'s device tier reports and '
                're-runs the scheduler — as if the phone switched zones. The '
                'schedule deliberately stays put: home and destination days '
                'keep their trip zones, and only a high-confidence '
                'live-location signal can override today. The device tier is '
                'the resolver\'s fallback for when a trip\'s own zones can\'t '
                'resolve.',
            current: deviceSource.overrideIana == null
                ? 'Using real device zone'
                : 'Override: ${deviceSource.overrideIana}',
            content: _ZonePicker(
              value: _device,
              onChanged: (v) => setState(() => _device = v),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  deviceSource.overrideIana = _device;
                  _reschedule(RescheduleTrigger.timezoneChanged,
                      'Device zone overridden to $_device');
                },
                child: const Text('Apply'),
              ),
              OutlinedButton(
                onPressed: () {
                  deviceSource.overrideIana = null;
                  _reschedule(RescheduleTrigger.timezoneChanged,
                      'Device zone reset');
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          _Card(
            title: 'Force a DST-transition reschedule',
            description:
                'Re-runs the scheduler with the dstTransition trigger. The DST '
                'gap/overlap math itself is verified by the unit tests — a '
                'simulator can\'t move the device clock across a real boundary, '
                'which is exactly why that seam exists.',
            content: const SizedBox.shrink(),
            actions: [
              FilledButton(
                onPressed: () => _reschedule(RescheduleTrigger.dstTransition,
                    'Rescheduled (dstTransition)'),
                child: const Text('Reschedule'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZonePicker extends StatelessWidget {
  const _ZonePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: [
        for (final z in kCommonZones)
          DropdownMenuItem(value: z, child: Text(z)),
      ],
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.description,
    required this.content,
    required this.actions,
    this.current,
  });

  final String title;
  final String description;
  final Widget content;
  final List<Widget> actions;
  final String? current;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            content,
            if (current != null) ...[
              const SizedBox(height: 8),
              Text(current!, style: Theme.of(context).textTheme.labelMedium),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}
