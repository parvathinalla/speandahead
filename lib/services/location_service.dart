import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLocationStatus {
  ready,
  servicesDisabled,
  denied,
  deniedForever,
  unavailable,
}

class AppLocationResult {
  final AppLocationStatus status;
  final Position? position;
  final String message;

  const AppLocationResult(this.status, this.message, [this.position]);
}

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  static const _promptAttemptedKey = 'initial_location_prompt_attempted';
  Future<AppLocationResult>? _inFlight;
  AppLocationResult? _lastResult;

  Future<AppLocationResult> initialize({bool requestAgain = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!requestAgain && _lastResult?.status == AppLocationStatus.ready) {
      return Future.value(_lastResult!);
    }
    final request = _resolve(requestAgain: requestAgain).timeout(
      const Duration(seconds: 20),
      onTimeout: () => _remember(const AppLocationResult(
        AppLocationStatus.unavailable,
        'Location lookup timed out. Check browser location permissions, '
        'then retry or enter the merchant manually.',
      )),
    );
    _inFlight = request;
    return request.whenComplete(() {
      if (identical(_inFlight, request)) _inFlight = null;
    });
  }

  Future<AppLocationResult> refresh() => initialize(requestAgain: true);

  Future<AppLocationResult> _resolve({required bool requestAgain}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _remember(
          const AppLocationResult(
            AppLocationStatus.servicesDisabled,
            'Turn on Location Services to find nearby merchants.',
          ),
        );
      }

      var permission = await Geolocator.checkPermission();
      if (!kIsWeb && permission == LocationPermission.denied) {
        final preferences = await SharedPreferences.getInstance();
        final attempted = preferences.getBool(_promptAttemptedKey) ?? false;
        if (!attempted || requestAgain) {
          await preferences.setBool(_promptAttemptedKey, true);
          permission = await Geolocator.requestPermission();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return _remember(
          const AppLocationResult(
            AppLocationStatus.deniedForever,
            kIsWeb
                ? 'Location permission is blocked. Allow location for this site in your browser, then retry.'
                : 'Location permission is blocked. Enable it in system settings or enter the merchant manually.',
          ),
        );
      }
      if (!kIsWeb && permission == LocationPermission.denied) {
        return _remember(
          const AppLocationResult(
            AppLocationStatus.denied,
            'Location access was not granted. You can enter the merchant manually.',
          ),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Web requestPermission performs an extra unbounded position lookup.
          // getCurrentPosition prompts once and applies the browser timeout.
          accuracy: kIsWeb ? LocationAccuracy.medium : LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _remember(
        AppLocationResult(
          AppLocationStatus.ready,
          'Current location found.',
          position,
        ),
      );
    } on PermissionDeniedException {
      return _remember(const AppLocationResult(
        AppLocationStatus.denied,
        'Location access was denied. Allow location for this site in your browser, then retry.',
      ));
    } on TimeoutException {
      return _remember(const AppLocationResult(
        AppLocationStatus.unavailable,
        'The device did not return a location in time. Check location services or try another browser.',
      ));
    } catch (_) {
      return _remember(
        const AppLocationResult(
          AppLocationStatus.unavailable,
          'Your location could not be determined. Enter the merchant manually or try again.',
        ),
      );
    }
  }

  AppLocationResult _remember(AppLocationResult value) {
    _lastResult = value;
    return value;
  }

  AppLocationResult? get lastResult => _lastResult;

  Future<bool> openSettings() async =>
      kIsWeb ? false : await Geolocator.openAppSettings();
}
