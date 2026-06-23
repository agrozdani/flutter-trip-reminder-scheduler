import 'package:flutter/material.dart';

import 'home_shell.dart';

/// Root widget. Intentionally minimal — the scheduling engine is the star, not
/// the chrome around it.
class TripReminderApp extends StatelessWidget {
  const TripReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trip Reminder Scheduler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D7EFF),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
