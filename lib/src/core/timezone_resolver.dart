import 'package:timezone/timezone.dart' as tz;

import 'models/resolved_zone.dart';
import 'ports/country_zone_map.dart';
import 'ports/device_timezone_source.dart';
import 'ports/location_zone_source.dart';

/// Resolves the best available timezone for scheduling, reporting *how* and
/// *how confidently* it resolved.
///
/// The cascade goes from most to least trustworthy and stops at the first hit:
///
/// 1. live location  (high)
/// 2. device timezone (medium)
/// 3. last-known zone (low)
/// 4. country heuristic (medium, or low for multi-zone countries)
/// 5. device-locale country (fallback)
/// 6. UTC (fallback)
///
/// It depends only on three narrow ports, so every tier is reproducible in a
/// plain unit test with fakes — no GPS, network, or device clock involved.
class TimezoneResolver {
  TimezoneResolver({
    required DeviceTimezoneSource deviceSource,
    required LocationZoneSource locationSource,
    required CountryZoneMap countryMap,
  })  : _device = deviceSource,
        _location = locationSource,
        _countries = countryMap;

  final DeviceTimezoneSource _device;
  final LocationZoneSource _location;
  final CountryZoneMap _countries;

  /// The full priority cascade. [destinationCountry] enables the country tier;
  /// [allowLocation] toggles the live-location tier; [lastKnownIana] and
  /// [localeCountry] feed the lower tiers (supplied by the caller so this stays
  /// pure).
  Future<ResolvedZone> resolveCascade({
    String? destinationCountry,
    bool allowLocation = true,
    String? lastKnownIana,
    String? localeCountry,
  }) async {
    // 1. Live location.
    if (allowLocation) {
      final iana = await _location.currentIana();
      final loc = _tryLocation(iana);
      if (loc != null) {
        return ResolvedZone(
          iana: iana!,
          location: loc,
          source: ZoneSource.liveLocation,
          confidence: ZoneConfidence.high,
        );
      }
    }

    // 2. Device timezone.
    final deviceIana = _normalize(await _device.currentIana());
    final deviceLoc = _tryLocation(deviceIana);
    if (deviceLoc != null) {
      return ResolvedZone(
        iana: deviceIana!,
        location: deviceLoc,
        source: ZoneSource.deviceTimezone,
        confidence: ZoneConfidence.medium,
      );
    }

    // 3. Last-known persisted zone.
    final lastLoc = _tryLocation(lastKnownIana);
    if (lastLoc != null) {
      return ResolvedZone(
        iana: lastKnownIana!,
        location: lastLoc,
        source: ZoneSource.lastKnown,
        confidence: ZoneConfidence.low,
        fallbackReason: 'Reusing last known zone',
      );
    }

    // 4. Country heuristic.
    if (destinationCountry != null && destinationCountry.isNotEmpty) {
      final z = _fromCountry(destinationCountry);
      if (z != null) return z;
    }

    // 5. Device-locale country.
    if (localeCountry != null && localeCountry.isNotEmpty) {
      final iana = _countries.ianaFor(localeCountry);
      final loc = _tryLocation(iana);
      if (loc != null) {
        return ResolvedZone(
          iana: iana!,
          location: loc,
          source: ZoneSource.localeFallback,
          confidence: ZoneConfidence.fallback,
          detectedCountry: localeCountry,
          fallbackReason: 'Resolved from device locale',
        );
      }
    }

    // 6. UTC last resort.
    return _utc('All timezone resolution tiers exhausted');
  }

  /// For destination days: the country heuristic first, then the device zone,
  /// then UTC. Never consults live location (you are scheduling for a place you
  /// are not yet at).
  Future<ResolvedZone> resolveForDestination(String country) async {
    final fromCountry = _fromCountry(country);
    if (fromCountry != null) return fromCountry;

    final deviceIana = _normalize(await _device.currentIana());
    final deviceLoc = _tryLocation(deviceIana);
    if (deviceLoc != null) {
      return ResolvedZone(
        iana: deviceIana!,
        location: deviceLoc,
        source: ZoneSource.deviceTimezone,
        confidence: ZoneConfidence.medium,
        fallbackReason: 'Unknown country "$country"; using device zone',
      );
    }
    return _utc('Could not resolve destination "$country"');
  }

  /// For the "today" candidate: the full cascade with live location enabled.
  Future<ResolvedZone> resolveForCurrentZone({
    String? lastKnownIana,
    String? localeCountry,
  }) =>
      resolveCascade(
        allowLocation: true,
        lastKnownIana: lastKnownIana,
        localeCountry: localeCountry,
      );

  /// For home days: honor the user's chosen zone if it is valid — reported as
  /// [ZoneSource.userChosen] at high confidence, since an explicit choice
  /// outranks any inferred signal. Only an invalid id falls into the cascade
  /// (with the location tier disabled).
  Future<ResolvedZone> resolveHomeZone(String preferredIana) async {
    final loc = _tryLocation(preferredIana);
    if (loc != null) {
      return ResolvedZone(
        iana: preferredIana,
        location: loc,
        source: ZoneSource.userChosen,
        confidence: ZoneConfidence.high,
      );
    }
    return resolveCascade(allowLocation: false);
  }

  ResolvedZone? _fromCountry(String country) {
    final iana = _countries.ianaFor(country);
    final loc = _tryLocation(iana);
    if (loc == null) return null;
    final multi = _countries.hasMultiple(country);
    return ResolvedZone(
      iana: iana!,
      location: loc,
      source: ZoneSource.countryHeuristic,
      confidence: multi ? ZoneConfidence.low : ZoneConfidence.medium,
      detectedCountry: country,
      fallbackReason:
          multi ? 'Country spans multiple zones; using its primary zone' : null,
    );
  }

  ResolvedZone _utc(String reason) => ResolvedZone(
        iana: 'UTC',
        location: tz.UTC,
        source: ZoneSource.utcFallback,
        confidence: ZoneConfidence.fallback,
        fallbackReason: reason,
      );

  tz.Location? _tryLocation(String? iana) {
    if (iana == null || iana.isEmpty) return null;
    try {
      return tz.getLocation(iana);
    } catch (_) {
      return null;
    }
  }

  /// Light normalization of a device-reported zone name. Anything already valid
  /// passes through untouched; a bare `GMT±N`/`UTC±N` becomes the matching
  /// `Etc/GMT∓N` — note the deliberate sign inversion, the classic IANA gotcha
  /// (`Etc/GMT-3` is actually UTC+3).
  String? _normalize(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    try {
      tz.getLocation(trimmed);
      return trimmed;
    } catch (_) {
      // not a valid IANA id; try offset normalization
    }
    final match = RegExp(r'^(?:GMT|UTC)([+-])(\d{1,2})$').firstMatch(trimmed);
    if (match != null) {
      final invertedSign = match.group(1) == '+' ? '-' : '+';
      final hours = int.parse(match.group(2)!);
      final candidate = 'Etc/GMT$invertedSign$hours';
      try {
        tz.getLocation(candidate);
        return candidate;
      } catch (_) {
        // fall through
      }
    }
    return trimmed; // let _tryLocation reject it
  }
}
