import '../core/ports/device_timezone_source.dart';

/// A [DeviceTimezoneSource] that reports a UI-set override if present, else the
/// real platform timezone.
///
/// A simulator can't actually change the device's timezone, so this is how the
/// "simulate a device timezone change" control works: set [override] and trigger
/// a reschedule, and the resolver behaves exactly as if the system zone changed.
class OverridableDeviceTimezoneSource implements DeviceTimezoneSource {
  OverridableDeviceTimezoneSource(this._platform);

  final DeviceTimezoneSource _platform;

  /// When non-null, this zone is reported instead of the platform's.
  String? overrideIana;

  @override
  Future<String?> currentIana() async =>
      overrideIana ?? await _platform.currentIana();
}
