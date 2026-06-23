import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/trip.dart';

/// Persists the user's trip definitions (not the schedule — that is the
/// [RegistryStore]'s job). Kept simple: a JSON array under one key.
///
/// Trips must survive a relaunch so launch-time recovery can rebuild the
/// schedule without the UI being open.
class PrefsTripStore {
  PrefsTripStore(this._prefs, {this.key = 'trips_v1'});

  final SharedPreferences _prefs;
  final String key;

  Future<List<Trip>> load() async {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Trip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<Trip> trips) async {
    await _prefs.setString(
      key,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }
}
