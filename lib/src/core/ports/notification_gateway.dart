import '../models/scheduled_reminder.dart';

/// The seam between "decide what to schedule" (pure) and "tell the OS" (plugin).
///
/// The engine produces [ScheduledReminder]s; this gateway turns them into real
/// pending OS notifications. Content (title/body) is passed in by the caller so
/// the gateway stays free of any domain vocabulary. Tests inject a fake that
/// just records ids — and can report an empty [pendingIds] to simulate the OS
/// clearing everything on reboot.
abstract interface class NotificationGateway {
  /// Schedules (or overwrites, since ids are deterministic) one reminder.
  Future<void> schedule(
    ScheduledReminder reminder, {
    required String title,
    required String body,
  });

  /// Cancels a single pending notification by id.
  Future<void> cancel(int id);

  /// Cancels everything this app has pending.
  Future<void> cancelAll();

  /// Ids the OS currently reports as pending. Compared against the registry to
  /// detect OS-cleared schedules.
  Future<List<int>> pendingIds();
}
