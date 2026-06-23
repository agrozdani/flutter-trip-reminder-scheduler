/// Maps a country name to an IANA timezone — the "country heuristic" tier.
///
/// The production app shipped a ~195-country table with state-level refinement.
/// This demo ships about a dozen entries behind this interface; the interesting
/// behavior to preserve is that a country spanning multiple zones resolves at
/// *lower confidence*, which [hasMultiple] reports.
abstract interface class CountryZoneMap {
  /// Primary IANA zone for [country], or null if the country is unknown.
  String? ianaFor(String country);

  /// True when [country] spans more than one timezone (degrades confidence).
  bool hasMultiple(String country);

  /// All known country names, for the destination picker.
  List<String> get countries;
}
