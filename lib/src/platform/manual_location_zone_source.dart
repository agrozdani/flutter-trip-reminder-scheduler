import '../core/ports/location_zone_source.dart';

/// A [LocationZoneSource] driven by the UI rather than by GPS.
///
/// The "Simulate I'm in zone X today" control sets [zone]; clearing it (null)
/// means "no live signal", so the resolver falls back to the device zone. This
/// is the demo's stand-in for the production GPS + reverse-geocoding path, and
/// it makes the "today overrides via location" behavior trivial to exercise by
/// hand or in a test.
class ManualLocationZoneSource implements LocationZoneSource {
  ManualLocationZoneSource([this.zone]);

  /// The currently simulated zone, or null when there is no live signal.
  String? zone;

  @override
  Future<String?> currentIana() async => zone;
}
