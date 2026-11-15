import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'ports/clock.dart';

/// How serious a [LogRecord] is. Sinks choose which levels to keep; the
/// in-app [LogBuffer] keeps all of them.
enum LogLevel {
  debug('D'),
  info('I'),
  warning('W'),
  error('E');

  const LogLevel(this.letter);

  /// One-letter code used in formatted lines.
  final String letter;

  bool atLeast(LogLevel other) => index >= other.index;
}

/// One structured log entry: a stable [event] name plus key/value [fields],
/// rather than a free-form sentence, so entries can be filtered, compared
/// across runs, and forwarded to a monitoring backend as they are.
class LogRecord {
  LogRecord({
    required this.sequence,
    required this.timeUtc,
    required this.level,
    required this.tag,
    required this.event,
    Map<String, Object?> fields = const {},
    this.error,
    this.stackTrace,
  }) : fields = Map.unmodifiable(fields);

  /// Position in this process's log, starting at 1. A gap means entries were
  /// lost (dropped from a full buffer, or rejected by a sink).
  final int sequence;

  final DateTime timeUtc;
  final LogLevel level;

  /// The component that wrote it: `scheduler`, `gateway`, ...
  final String tag;

  /// What happened, as a stable dotted name: `run.done`, `schedule.clamped`.
  final String event;

  /// Copied when the record is made, so a caller changing its map later
  /// can't rewrite the record.
  final Map<String, Object?> fields;

  final Object? error;
  final StackTrace? stackTrace;

  /// The fields as `key=value` pairs, then the error, if any.
  String get details {
    final parts = [
      for (final MapEntry(:key, :value) in fields.entries)
        '$key=${_render(value)}',
      if (error != null) 'error=${_render(_describe(error!))}',
    ];
    return parts.join(' ');
  }

  /// `2026-11-15T09:00:00.000Z W gateway schedule.clamped id=7 ...`
  String get line {
    final rest = details;
    final head = '${timeUtc.toIso8601String()} ${level.letter} $tag $event';
    return rest.isEmpty ? head : '$head $rest';
  }

  /// [line], followed by the stack trace when there is one.
  String format() {
    final stack = stackTrace?.toString().trimRight();
    return stack == null || stack.isEmpty ? line : '$line\n$stack';
  }

  @override
  String toString() => line;
}

/// Where log records go: the console, the in-app buffer, or an adapter for a
/// crash or monitoring service.
abstract interface class LogSink {
  /// Must not assume it is called on any particular schedule. A sink that
  /// throws is skipped for that record; the caller never sees the error.
  void write(LogRecord record);
}

/// The logging facade every component writes through.
///
/// A component takes a [Logger] in its constructor and defaults to
/// [Logger.silent], so nothing logs unless the app wires it up, and tests can
/// pass a [LogBuffer] and assert on what was written. [tagged] gives each
/// component its own name over the same sinks.
///
/// Logging never throws into the caller: a value whose `toString` throws is
/// rendered as a placeholder, and a sink that throws is skipped.
class Logger {
  /// A logger writing to [sinks], tagged [tag].
  Logger(List<LogSink> sinks, {String tag = 'app'})
    : this._(_Fanout(List.unmodifiable(sinks)), tag);

  Logger._(this._fanout, this.tag);

  /// Writes nowhere. The default for components that aren't given a logger.
  static final Logger silent = Logger(const []);

  final _Fanout _fanout;

  /// Name stamped on every record this logger writes.
  final String tag;

  /// The same sinks, under another [tag].
  Logger tagged(String tag) => Logger._(_fanout, tag);

  void debug(String event, [Map<String, Object?> fields = const {}]) =>
      _fanout.emit(LogLevel.debug, tag, event, fields, null, null);

  void info(String event, [Map<String, Object?> fields = const {}]) =>
      _fanout.emit(LogLevel.info, tag, event, fields, null, null);

  void warning(
    String event, [
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  ]) => _fanout.emit(LogLevel.warning, tag, event, fields, error, stackTrace);

  void error(
    String event, [
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  ]) => _fanout.emit(LogLevel.error, tag, event, fields, error, stackTrace);
}

/// Shared by a logger and every [Logger.tagged] copy of it, so they number
/// their records in one sequence.
class _Fanout {
  _Fanout(this._sinks);

  final List<LogSink> _sinks;
  int _sequence = 0;
  bool _writing = false;

  void emit(
    LogLevel level,
    String tag,
    String event,
    Map<String, Object?> fields,
    Object? error,
    StackTrace? stackTrace,
  ) {
    // A sink that logs while writing would otherwise recurse without end.
    if (_sinks.isEmpty || _writing) return;
    _writing = true;
    try {
      final record = LogRecord(
        sequence: ++_sequence,
        timeUtc: clock.now().toUtc(),
        level: level,
        tag: tag,
        event: event,
        fields: fields,
        error: error,
        stackTrace: stackTrace,
      );
      for (final sink in _sinks) {
        try {
          sink.write(record);
        } catch (_) {
          // A broken sink must not break the app, or the other sinks.
        }
      }
    } finally {
      _writing = false;
    }
  }
}

/// Keeps the latest [capacity] records in memory, for the in-app log screen
/// and for copying into a bug report. The oldest are dropped first, and
/// [dropped] counts them.
class LogBuffer implements LogSink {
  LogBuffer({this.capacity = 1000}) : assert(capacity > 0);

  final int capacity;
  final Queue<LogRecord> _records = ListQueue();
  final StreamController<void> _changes = StreamController.broadcast();
  int _dropped = 0;

  /// Oldest first.
  List<LogRecord> get records => List.unmodifiable(_records);

  /// How many records have been dropped to stay within [capacity] since the
  /// buffer was made or last cleared.
  int get dropped => _dropped;

  /// Fires after every write and [clear].
  Stream<void> get changes => _changes.stream;

  @override
  void write(LogRecord record) {
    _records.addLast(record);
    while (_records.length > capacity) {
      _records.removeFirst();
      _dropped++;
    }
    _notify();
  }

  void clear() {
    _records.clear();
    _dropped = 0;
    _notify();
  }

  /// Every record at [minLevel] or above, one per line with stack traces,
  /// oldest first, for pasting into a bug report.
  String export({LogLevel minLevel = LogLevel.debug}) {
    final out = StringBuffer();
    if (_dropped > 0) {
      out.writeln('($_dropped earlier entries dropped)');
    }
    for (final record in _records) {
      if (record.level.atLeast(minLevel)) out.writeln(record.format());
    }
    return out.toString();
  }

  Future<void> close() => _changes.close();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }
}

/// Longest a single rendered value may be before it is cut short.
const int _maxValueLength = 300;

String _render(Object? value) {
  String text;
  try {
    text = switch (value) {
      null => 'null',
      DateTime() => value.toUtc().toIso8601String(),
      Duration() => '${value.inMilliseconds}ms',
      Enum() => value.name,
      _ => value.toString(),
    };
  } catch (_) {
    text = '<unprintable ${value.runtimeType}>';
  }
  if (text.length > _maxValueLength) {
    text = '${text.substring(0, _maxValueLength)}…';
  }
  final needsQuotes = text.isEmpty || text.contains(_needsQuoting);
  return needsQuotes ? jsonEncode(text) : text;
}

/// Whitespace, a quote, `=`, or any other control character.
final RegExp _needsQuoting = RegExp(r'[\s"=\x00-\x1f]');

String _describe(Object error) {
  try {
    final text = error.toString();
    // Name the type unless the text already does ("FormatException: ...");
    // a StateError reads only "Bad state: ...".
    final type = error.runtimeType.toString();
    return text.startsWith(type) ? text : '$type: $text';
  } catch (_) {
    return '<unprintable ${error.runtimeType}>';
  }
}
