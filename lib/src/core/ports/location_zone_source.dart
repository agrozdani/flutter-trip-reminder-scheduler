/// A live "I am physically here right now" timezone signal.
///
/// In the production app this came from GPS + reverse-geocoding and was only
/// emitted at high confidence. Here it is deliberately reduced to a single
/// method driven by a UI toggle — enough to exercise the "today overrides via
/// location" path without any real geocoding. A null result means "no live
/// signal", in which case the resolver falls through to the device zone.
abstract interface class LocationZoneSource {
  /// The IANA zone of the current live location, or null if none is available.
  Future<String?> currentIana();
}
