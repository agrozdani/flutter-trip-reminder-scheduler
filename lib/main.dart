import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/app.dart';
import 'src/app/providers.dart';
import 'src/platform/notification_bootstrap.dart';

/// Initializes the async singletons (preferences + the notification plugin and
/// timezone database) once, then injects them into the provider graph. The rest
/// of the app resolves its dependencies from there.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final plugin = await NotificationBootstrap.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationPluginProvider.overrideWithValue(plugin),
      ],
      child: const TripReminderApp(),
    ),
  );
}
