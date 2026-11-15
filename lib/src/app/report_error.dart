import 'package:flutter/foundation.dart';

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
