import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging.dart';
import '../providers.dart';

/// The in-app log, newest first: what the scheduler, engine, and adapters
/// recorded in this process. Filter by level, copy what's shown into a bug
/// report, or clear it.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  LogLevel _minLevel = LogLevel.debug;

  Future<void> _copy(LogBuffer buffer) async {
    await Clipboard.setData(
      ClipboardData(text: buffer.export(minLevel: _minLevel)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Log copied')));
  }

  @override
  Widget build(BuildContext context) {
    final buffer = ref.watch(logBufferProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(buffer),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: buffer.clear,
          ),
        ],
      ),
      body: StreamBuilder<void>(
        stream: buffer.changes,
        builder: (context, _) {
          final shown = [
            for (final r in buffer.records.reversed)
              if (r.level.atLeast(_minLevel)) r,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final level in LogLevel.values)
                      ChoiceChip(
                        label: Text(level.name),
                        selected: level == _minLevel,
                        onSelected: (_) => setState(() => _minLevel = level),
                      ),
                  ],
                ),
              ),
              if (buffer.dropped > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '${buffer.dropped} older entries dropped',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('Nothing logged at this level'))
                    : ListView.separated(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _RecordTile(shown[i]),
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

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.record);

  final LogRecord record;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(record.level);
    final time = record.timeUtc.toIso8601String().substring(11, 23);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${record.level.letter} ',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: '${record.tag} ${record.event}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '  ${time}Z',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (record.details.isNotEmpty)
            Text(
              record.details,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
        ],
      ),
    );
  }
}

Color _levelColor(LogLevel level) => switch (level) {
  LogLevel.debug => Colors.grey,
  LogLevel.info => Colors.blue,
  LogLevel.warning => Colors.orange,
  LogLevel.error => Colors.red,
};
