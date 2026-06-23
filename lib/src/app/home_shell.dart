import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/reschedule_trigger.dart';
import 'providers.dart';
import 'screens/simulate_screen.dart';
import 'screens/trips_screen.dart';
import 'screens/upcoming_reminders_screen.dart';

/// Three-tab shell. On first build it runs launch-time recovery so a reboot,
/// long absence, or DST shift while the app was closed is reconciled before the
/// user does anything; thereafter every return to the foreground funnels an
/// [RescheduleTrigger.appResume] through the same coordinator.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;

  static const List<Widget> _tabs = [
    TripsScreen(),
    UpcomingRemindersScreen(),
    SimulateScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(schedulerProvider).recoverOnLaunch();
      if (mounted) ref.invalidate(upcomingRemindersProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only a return to the foreground reschedules. The coordinator debounces and
    // de-duplicates, so repeated resumes never storm; and because a reschedule is
    // an idempotent reconcile, a pass with nothing to change costs no OS calls.
    if (state == AppLifecycleState.resumed) {
      unawaited(_rescheduleOnResume());
    }
  }

  Future<void> _rescheduleOnResume() async {
    await ref.read(schedulerProvider).request(RescheduleTrigger.appResume);
    if (mounted) ref.invalidate(upcomingRemindersProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.flight_takeoff), label: 'Trips'),
          NavigationDestination(
              icon: Icon(Icons.notifications_outlined), label: 'Upcoming'),
          NavigationDestination(
              icon: Icon(Icons.science_outlined), label: 'Simulate'),
        ],
      ),
    );
  }
}
