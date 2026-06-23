import 'package:timezone/timezone.dart' as tz;

/// Where a timezone was resolved from. Ordered by how much we trust it, most
/// trustworthy first. Persisted alongside every scheduled reminder so the
/// schedule can explain *why* it chose the zone it did.
enum ZoneSource {
  /// A live location signal (in this demo, a simulated "I'm here now" zone).
  liveLocation,

  /// The device's own system timezone.
  deviceTimezone,

  /// A previously persisted zone, reused when nothing better is available.
  lastKnown,

  /// A country name mapped to an IANA zone via a lookup table.
  countryHeuristic,

  /// The device locale's country, the weakest non-UTC signal.
  localeFallback,

  /// Nothing resolved; UTC as an absolute last resort.
  utcFallback,
}

/// How much to trust a [ResolvedZone]. This is *timezone-resolution*
/// confidence, not GPS accuracy.
enum ZoneConfidence { high, medium, low, fallback }

/// The result of resolving a timezone, carrying its own provenance.
///
/// The whole point of this type is that a resolver returns *why* and *how
/// sure* it is, not just a bare IANA string. The UI surfaces this so a reminder
/// scheduled against `Africa/Lagos (countryHeuristic, low)` is visibly
/// different from one scheduled against `Europe/London (liveLocation, high)`.
class ResolvedZone {
  ResolvedZone({
    required this.iana,
    required this.location,
    required this.source,
    required this.confidence,
    this.fallbackReason,
    this.detectedCountry,
  });

  /// IANA timezone id, e.g. `America/New_York`.
  final String iana;

  /// The resolved zone from the `timezone` package, used for instant math.
  final tz.Location location;

  /// How this zone was resolved.
  final ZoneSource source;

  /// How much to trust it.
  final ZoneConfidence confidence;

  /// Human-readable note when a resolution fell back or was degraded.
  final String? fallbackReason;

  /// Country name when the zone came from a country, for context.
  final String? detectedCountry;

  ResolvedZone copyWith({
    String? iana,
    tz.Location? location,
    ZoneSource? source,
    ZoneConfidence? confidence,
    String? fallbackReason,
    String? detectedCountry,
  }) {
    return ResolvedZone(
      iana: iana ?? this.iana,
      location: location ?? this.location,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      fallbackReason: fallbackReason ?? this.fallbackReason,
      detectedCountry: detectedCountry ?? this.detectedCountry,
    );
  }

  Map<String, dynamic> toJson() => {
        'iana': iana,
        'source': source.name,
        'confidence': confidence.name,
        if (fallbackReason != null) 'fallbackReason': fallbackReason,
        if (detectedCountry != null) 'detectedCountry': detectedCountry,
      };

  @override
  bool operator ==(Object other) =>
      other is ResolvedZone &&
      other.iana == iana &&
      other.source == source &&
      other.confidence == confidence &&
      other.fallbackReason == fallbackReason &&
      other.detectedCountry == detectedCountry;

  @override
  int get hashCode =>
      Object.hash(iana, source, confidence, fallbackReason, detectedCountry);

  @override
  String toString() =>
      'ResolvedZone($iana, ${source.name}, ${confidence.name})';
}
