import 'package:flutter/foundation.dart';

import '../core/logging.dart';

/// Reports a failed reschedule through [FlutterError] instead of leaving it
/// unhandled.
///
/// Nothing else is needed to recover: a failed run records only the changes
/// that reached the OS, so the next trigger diffs from those and applies the
/// rest.
void reportRescheduleError(Object error, StackTrace stack, String activity) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'trip_reminder_scheduler',
      context: ErrorDescription('while $activity'),
    ),
  );
}

/// Sends every error Flutter reports, and every error nothing caught, to
/// [log] as well as to the handlers already installed, which still run.
void installErrorLogging(Logger log) {
  final flutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    log.error(
      'flutter',
      {'library': details.library, 'context': details.context?.toString()},
      details.exception,
      details.stack,
    );
    flutterOnError?.call(details);
  };

  final dispatcher = PlatformDispatcher.instance;
  final platformOnError = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    log.error('uncaught', const {}, error, stack);
    // False lets the platform report it too, as it would without this hook.
    return platformOnError?.call(error, stack) ?? false;
  };
}
