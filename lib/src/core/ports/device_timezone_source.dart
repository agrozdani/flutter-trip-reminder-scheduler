/// Reports the device's current system timezone as an IANA id.
///
/// Wrapping `flutter_timezone` behind this one-method interface is what lets the
/// resolver run in a plain `dart test` with a fake that returns any zone we like.
abstract interface class DeviceTimezoneSource {
  /// The device's IANA timezone (e.g. `Europe/Berlin`), or null if unavailable.
  Future<String?> currentIana();
}
