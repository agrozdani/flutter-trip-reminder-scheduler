import 'package:flutter_timezone/flutter_timezone.dart';

import '../core/logging.dart';
import '../core/ports/device_timezone_source.dart';

/// [DeviceTimezoneSource] backed by the `flutter_timezone` plugin.
class FlutterTimezoneDeviceSource implements DeviceTimezoneSource {
  const FlutterTimezoneDeviceSource({this._log});

  final Logger? _log;

  @override
  Future<String?> currentIana() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return info.identifier;
    } catch (error, stack) {
      // The resolver falls through to its lower tiers.
      _log?.warning('unavailable', const {}, error, stack);
      return null;
    }
  }
}
