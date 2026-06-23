import '../core/ports/country_zone_map.dart';

/// A deliberately tiny country→zone table — about a dozen countries — standing
/// in for the production app's ~195-country dataset.
///
/// What matters for the demo is preserved: several entries (United States,
/// Brazil, Australia) span multiple zones, so resolving them yields *lower
/// confidence*. The primary (first) zone is used as the representative.
class SmallCountryZoneMap implements CountryZoneMap {
  const SmallCountryZoneMap();

  static const Map<String, List<String>> _data = {
    'United Kingdom': ['Europe/London'],
    'France': ['Europe/Paris'],
    'Germany': ['Europe/Berlin'],
    'Nigeria': ['Africa/Lagos'],
    'Kenya': ['Africa/Nairobi'],
    'United Arab Emirates': ['Asia/Dubai'],
    'India': ['Asia/Kolkata'],
    'Japan': ['Asia/Tokyo'],
    'New Zealand': ['Pacific/Auckland'],
    // Multi-zone countries: primary zone used, confidence degraded.
    'United States': [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
    ],
    'Brazil': ['America/Sao_Paulo', 'America/Manaus', 'America/Rio_Branco'],
    'Australia': ['Australia/Sydney', 'Australia/Perth', 'Australia/Adelaide'],
  };

  @override
  String? ianaFor(String country) => _data[country]?.first;

  @override
  bool hasMultiple(String country) => (_data[country]?.length ?? 0) > 1;

  @override
  List<String> get countries => _data.keys.toList()..sort();
}
