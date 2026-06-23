/// A curated list of IANA zones for the demo's dropdowns (home zone, simulated
/// location, device-timezone override). Chosen to span offsets, hemispheres,
/// half-hour offsets, and both DST and no-DST behaviors.
const List<String> kCommonZones = [
  'Pacific/Honolulu', // UTC-10, no DST
  'America/Anchorage',
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Sao_Paulo', // southern hemisphere
  'UTC',
  'Europe/London',
  'Europe/Paris',
  'Africa/Lagos', // UTC+1, no DST
  'Africa/Nairobi',
  'Asia/Dubai',
  'Asia/Kolkata', // UTC+5:30
  'Asia/Tokyo', // no DST
  'Australia/Sydney', // southern hemisphere DST
  'Pacific/Auckland',
];
