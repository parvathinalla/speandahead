@TestOn('browser')
library;

import 'package:creditpilot_mobile/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

class PendingPermissionLocation extends GeolocatorPlatform {
  int permissionRequests = 0;
  int positionRequests = 0;
  LocationSettings? settings;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.denied;
  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;
    throw StateError('Web must not make the unbounded permission lookup');
  }
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    positionRequests++;
    settings = locationSettings;
    return Position(latitude: 0, longitude: 0, timestamp: DateTime.utc(2026),
      accuracy: 100, altitude: 0, altitudeAccuracy: 0, heading: 0,
      headingAccuracy: 0, speed: 0, speedAccuracy: 0);
  }
}

void main() {
  test('Web obtains location in one bounded request while permission is pending', () async {
    final original = GeolocatorPlatform.instance;
    final platform = PendingPermissionLocation();
    GeolocatorPlatform.instance = platform;
    try {
      final result = await LocationService.instance.refresh();
      expect(result.status, AppLocationStatus.ready);
      expect(platform.permissionRequests, 0);
      expect(platform.positionRequests, 1);
      expect(platform.settings?.timeLimit, const Duration(seconds: 12));
      expect(platform.settings?.accuracy, LocationAccuracy.medium);
    } finally {
      GeolocatorPlatform.instance = original;
    }
  });
}
