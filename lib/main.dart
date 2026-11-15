import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/app.dart';
import 'src/app/providers.dart';
import 'src/app/report_error.dart';
import 'src/core/logging.dart';
import 'src/platform/console_log_sink.dart';
import 'src/platform/notification_bootstrap.dart';

/// Initializes the async singletons (preferences + the notification plugin and
/// timezone database) once, then injects them into the provider graph. The rest
/// of the app resolves its dependencies from there.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Logging first, so the rest of startup, and anything it throws, is logged.
  // The console gets debug entries only in debug builds; the in-app buffer
  // keeps every level.
  final logs = LogBuffer();
  final log = Logger([
    logs,
    ConsoleLogSink(minLevel: kDebugMode ? LogLevel.debug : LogLevel.info),
  ]);
  installErrorLogging(log.tagged('error'));
  log.info('start', {
    'build': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
    'platform': defaultTargetPlatform,
  });

  final prefs = await SharedPreferences.getInstance();
  final plugin = await NotificationBootstrap.init(log: log.tagged('bootstrap'));

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationPluginProvider.overrideWithValue(plugin),
        logBufferProvider.overrideWithValue(logs),
        loggerProvider.overrideWithValue(log),
      ],
      child: const TripReminderApp(),
    ),
  );
}
