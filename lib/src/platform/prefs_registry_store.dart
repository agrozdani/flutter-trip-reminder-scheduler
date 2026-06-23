import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/reminder_registry.dart';
import '../core/ports/registry_store.dart';

/// [RegistryStore] backed by `shared_preferences` (plain JSON).
///
/// The production app used an encrypted Hive box; this demo keeps persistence
/// deliberately boring so the scheduling logic stays the focus.
class PrefsRegistryStore implements RegistryStore {
  PrefsRegistryStore(this._prefs, {this.key = 'reminder_registry_v1'});

  final SharedPreferences _prefs;
  final String key;

  @override
  Future<ReminderRegistry> load() async {
    final raw = _prefs.getString(key);
    if (raw == null) return ReminderRegistry.empty;
    try {
      return ReminderRegistry.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Corrupt or schema-incompatible data: start clean rather than crash.
      return ReminderRegistry.empty;
    }
  }

  @override
  Future<void> save(ReminderRegistry registry) async {
    await _prefs.setString(key, jsonEncode(registry.toJson()));
  }
}
