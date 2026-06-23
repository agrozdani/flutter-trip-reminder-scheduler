import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// One-time platform setup for notifications: load the IANA timezone database
/// and initialize the plugin, then request the runtime permissions modern
/// Android and iOS require.
abstract final class NotificationBootstrap {
  /// Initializes timezone data and the notification plugin, returning the
  /// configured plugin instance for the gateway to use.
  static Future<FlutterLocalNotificationsPlugin> init() async {
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

    await _requestPermissions(plugin);
    return plugin;
  }

  static Future<void> _requestPermissions(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      // Needed for exactAllowWhileIdle on Android 12+.
      await android.requestExactAlarmsPermission();
    }

    final ios = plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
    }
  }
}
