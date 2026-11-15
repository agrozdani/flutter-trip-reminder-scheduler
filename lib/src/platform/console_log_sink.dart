import 'package:flutter/foundation.dart';

import '../core/logging.dart';

/// [LogSink] that prints through [debugPrint]: the `flutter run` console and
/// DevTools in debug builds, and logcat (tag `flutter`) or the iOS unified log
/// in release builds, so a device's log can be read without a debugger.
class ConsoleLogSink implements LogSink {
  ConsoleLogSink({this.minLevel = LogLevel.info});

  /// Records below this level are not printed.
  final LogLevel minLevel;

  @override
  void write(LogRecord record) {
    if (record.level.atLeast(minLevel)) debugPrint(record.format());
  }
}
