import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:trip_reminder_scheduler/src/core/models/resolved_zone.dart';
import 'package:trip_reminder_scheduler/src/core/timezone_resolver.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  TimezoneResolver build({String? device, String? location}) =>
      TimezoneResolver(
        deviceSource: FakeDeviceTimezoneSource(device),
        locationSource: FakeLocationZoneSource(location),
        countryMap: FakeCountryZoneMap(),
      );

  test('tier 1: live location wins when present (high confidence)', () async {
    final r = build(device: 'America/New_York', location: 'Europe/London');
    final z = await r.resolveCascade(destinationCountry: 'Nigeria');
    expect(z.iana, 'Europe/London');
    expect(z.source, ZoneSource.liveLocation);
    expect(z.confidence, ZoneConfidence.high);
  });

  test('tier 2: device timezone wins when there is no location', () async {
    final r = build(device: 'America/New_York');
    final z = await r.resolveCascade();
    expect(z.iana, 'America/New_York');
    expect(z.source, ZoneSource.deviceTimezone);
    expect(z.confidence, ZoneConfidence.medium);
  });

  test('tier 3: last-known wins when device is unavailable', () async {
    final r = build();
    final z = await r.resolveCascade(lastKnownIana: 'Asia/Tokyo');
    expect(z.iana, 'Asia/Tokyo');
    expect(z.source, ZoneSource.lastKnown);
    expect(z.confidence, ZoneConfidence.low);
  });

  test('tier 4: single-zone country resolves at medium confidence', () async {
    final r = build();
    final z = await r.resolveCascade(destinationCountry: 'Nigeria');
    expect(z.iana, 'Africa/Lagos');
    expect(z.source, ZoneSource.countryHeuristic);
    expect(z.confidence, ZoneConfidence.medium);
    expect(z.detectedCountry, 'Nigeria');
  });

  test('tier 4: multi-zone country downgrades to low confidence', () async {
    final r = build();
    final z = await r.resolveCascade(destinationCountry: 'United States');
    expect(z.iana, 'America/New_York', reason: 'primary zone');
    expect(z.source, ZoneSource.countryHeuristic);
    expect(z.confidence, ZoneConfidence.low);
    expect(z.fallbackReason, isNotNull);
  });

  test('tier 5: device-locale country is the weakest non-UTC tier', () async {
    final r = build();
    final z = await r.resolveCascade(localeCountry: 'Germany');
    expect(z.iana, 'Europe/Berlin');
    expect(z.source, ZoneSource.localeFallback);
    expect(z.confidence, ZoneConfidence.fallback);
  });

  test('tier 6: UTC when every tier fails', () async {
    final r = build();
    final z = await r.resolveCascade(destinationCountry: 'Atlantis');
    expect(z.iana, 'UTC');
    expect(z.source, ZoneSource.utcFallback);
    expect(z.confidence, ZoneConfidence.fallback);
    expect(z.fallbackReason, isNotNull);
  });

  test('resolveForDestination ignores live location', () async {
    final r = build(device: 'America/New_York', location: 'Europe/London');
    final z = await r.resolveForDestination('Japan');
    expect(z.iana, 'Asia/Tokyo');
    expect(z.source, ZoneSource.countryHeuristic);
  });

  test('resolveForDestination falls back to device for unknown country',
      () async {
    final r = build(device: 'America/New_York');
    final z = await r.resolveForDestination('Atlantis');
    expect(z.iana, 'America/New_York');
    expect(z.source, ZoneSource.deviceTimezone);
    expect(z.fallbackReason, contains('Atlantis'));
  });

  test('device-reported GMT offset normalizes to Etc/GMT (inverted sign)',
      () async {
    final r = build(device: 'GMT+3');
    final z = await r.resolveCascade();
    expect(z.iana, 'Etc/GMT-3', reason: 'UTC+3 is Etc/GMT-3 in IANA');
    expect(z.source, ZoneSource.deviceTimezone);
  });

  test('resolveHomeZone honors a valid preferred zone', () async {
    final r = build(device: 'America/New_York');
    final z = await r.resolveHomeZone('Europe/Paris');
    expect(z.iana, 'Europe/Paris');
    expect(z.source, ZoneSource.deviceTimezone);
  });
}
