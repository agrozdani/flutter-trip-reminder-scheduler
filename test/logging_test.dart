import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_reminder_scheduler/src/core/logging.dart';
import 'package:trip_reminder_scheduler/src/core/models/reschedule_trigger.dart';
import 'package:trip_reminder_scheduler/src/platform/console_log_sink.dart';

void main() {
  final at = DateTime.utc(2024, 6, 12, 9, 0, 5);

  test('a record renders as one line of stable key=value pairs', () {
    final buffer = LogBuffer();
    final fields = <String, Object?>{
      'trigger': RescheduleTrigger.userEdit,
      'due': DateTime.utc(2024, 6, 12, 9),
      'took': const Duration(milliseconds: 42),
      'zone': null,
      'reason': 'Country spans "two" zones',
    };
    withClock(Clock.fixed(at), () {
      Logger([buffer], tag: 'scheduler').error(
        'run.failed',
        fields,
        StateError('boom'),
        StackTrace.fromString('#0 main'),
      );
    });
    fields['trigger'] = 'changed later';

    final record = buffer.records.single;
    expect(
      record.line,
      '2024-06-12T09:00:05.000Z E scheduler run.failed '
      'trigger=userEdit due=2024-06-12T09:00:00.000Z took=42ms zone=null '
      r'reason="Country spans \"two\" zones" error="StateError: Bad state: boom"',
      reason: 'the record keeps the fields it was given, not later changes',
    );
    expect(record.format(), '${record.line}\n#0 main');
    expect(record.sequence, 1);
  });

  test('logging never throws, whatever the values or sinks do', () {
    final buffer = LogBuffer();
    final log = Logger([_ThrowingSink(), buffer]);

    log.info('odd', {'value': _Unprintable(), 'long': 'x' * 400});
    log.error('odd.error', const {}, _Unprintable());

    final first = buffer.records.first;
    expect(first.line, contains('value="<unprintable _Unprintable>"'));
    expect(first.fields['long'], hasLength(400));
    expect(
      first.details,
      endsWith(' long=${'x' * 300}…'),
      reason: 'long values are cut',
    );
    expect(
      buffer.records.last.line,
      contains('error="<unprintable _Unprintable>"'),
    );
    expect(buffer.records.map((r) => r.sequence), [
      1,
      2,
    ], reason: 'a sink that throws does not stop the sinks after it');
  });

  test(
    'the buffer keeps the newest records and counts what it drops',
    () async {
      final buffer = LogBuffer(capacity: 3);
      final log = Logger([buffer]).tagged('engine');
      var changes = 0;
      final sub = buffer.changes.listen((_) => changes++);

      for (var i = 1; i <= 5; i++) {
        (i.isEven ? log.warning : log.debug)('step', {'i': i});
      }
      await Future<void>.delayed(Duration.zero); // deliver the change events

      expect(buffer.records.map((r) => r.fields['i']), [3, 4, 5]);
      expect(buffer.dropped, 2);
      final exported = buffer.export(minLevel: LogLevel.warning);
      expect(exported, startsWith('(2 earlier entries dropped)\n'));
      expect(exported, contains(' W engine step i=4'));
      expect(exported, isNot(contains('i=3')));
      expect(changes, 5);

      buffer.clear();
      expect(buffer.records, isEmpty);
      expect(buffer.dropped, 0);
      await sub.cancel();
    },
  );

  test('the console prints from its level up, with the stack trace', () {
    final printed = <String?>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message);
    addTearDown(() => debugPrint = original);

    final log = Logger([ConsoleLogSink(minLevel: LogLevel.info)]);
    log.debug('quiet');
    log.info('loud');
    log.error('broken', const {}, 'cause', StackTrace.fromString('#0 here'));

    expect(printed, hasLength(2));
    expect(printed.first, endsWith(' I app loud'));
    expect(
      printed.last,
      endsWith(' E app broken error="String: cause"\n#0 here'),
    );
  });
}

class _ThrowingSink implements LogSink {
  @override
  void write(LogRecord record) => throw StateError('sink is broken');
}

class _Unprintable {
  @override
  String toString() => throw UnsupportedError('no');
}
