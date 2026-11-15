import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging.dart';
import '../core/models/reminder_registry.dart';
import '../core/ports/registry_store.dart';

/// [RegistryStore] backed by `shared_preferences` (plain JSON).
///
/// The production app used an encrypted Hive box; this demo keeps persistence
/// deliberately boring so the scheduling logic stays the focus.
class PrefsRegistryStore implements RegistryStore {
  PrefsRegistryStore(
    this._prefs, {
    this.key = 'reminder_registry_v1',
    Logger? log,
  }) : _log = log ?? Logger.silent;

  final SharedPreferences _prefs;
  final String key;
  final Logger _log;

  @override
  Future<ReminderRegistry> load() async {
    final raw = _prefs.getString(key);
    if (raw == null) return ReminderRegistry.empty;
    try {
      return ReminderRegistry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error, stack) {
      // Corrupt or schema-incompatible data: start clean rather than crash.
      // Whatever it tracked that no trip still wants is never cancelled, so
      // this is logged as an error, not passed over.
      _log.error(
        'load.unreadable',
        {'key': key, 'chars': raw.length},
        error,
        stack,
      );
      return ReminderRegistry.empty;
    }
  }

  @override
  Future<void> save(ReminderRegistry registry) async {
    await _prefs.setString(key, jsonEncode(registry.toJson()));
  }
}
