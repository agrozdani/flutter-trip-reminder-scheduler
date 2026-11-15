import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../core/logging.dart';

/// One-time platform setup for notifications: load the IANA timezone database
/// and initialize the plugin, then request the runtime permissions modern
/// Android and iOS require.
abstract final class NotificationBootstrap {
  /// Initializes timezone data and the notification plugin, returning the
  /// configured plugin instance for the gateway to use. Logs what each
  /// permission request returned.
  static Future<FlutterLocalNotificationsPlugin> init({Logger? log}) async {
    log ??= Logger.silent;
    // Must run before any tz.getLocation / TZDateTime use.
    tzdata.initializeTimeZones();

    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      // We request permissions explicitly below rather than at init.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    await _requestPermissions(plugin, log);
    return plugin;
  }

  static Future<void> _requestPermissions(
    FlutterLocalNotificationsPlugin plugin,
    Logger log,
  ) async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final notifications = await android.requestNotificationsPermission();
      // Needed for exactAllowWhileIdle on Android 12+.
      final exactAlarms = await android.requestExactAlarmsPermission();
      // Asked only to log it, so a failure must not stop the app starting.
      bool? canScheduleExact;
      try {
        canScheduleExact = await android.canScheduleExactNotifications();
      } catch (error, stack) {
        log.warning('exactAlarms.unknown', const {}, error, stack);
      }
      log.info('permissions', {
        'platform': 'android',
        'notifications': notifications,
        'exactAlarms': exactAlarms,
        'canScheduleExact': canScheduleExact,
      });
      if (canScheduleExact == false) {
        // The plugin then rejects every exactAllowWhileIdle schedule.
        log.warning('exactAlarms.denied');
      }
    }

    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      log.info('permissions', {'platform': 'ios', 'granted': granted});
    }
  }
}
