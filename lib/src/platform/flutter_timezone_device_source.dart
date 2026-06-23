import 'package:flutter_timezone/flutter_timezone.dart';

import '../core/ports/device_timezone_source.dart';

/// [DeviceTimezoneSource] backed by the `flutter_timezone` plugin.
class FlutterTimezoneDeviceSource implements DeviceTimezoneSource {
  const FlutterTimezoneDeviceSource();

  @override
  Future<String?> currentIana() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } catch (_) {
      return null;
    }
  }
}
