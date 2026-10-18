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
    if (!requestAgain && _inFlight != null) return _inFlight!;
    _inFlight = _resolve(requestAgain: requestAgain);
    return _inFlight!;
  }

  Future<AppLocationResult> refresh() => _resolve(requestAgain: true);

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
      if (permission == LocationPermission.denied) {
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
            'Location permission is blocked. Enable it in system settings or enter the merchant manually.',
          ),
        );
      }
      if (permission == LocationPermission.denied) {
        return _remember(
          const AppLocationResult(
            AppLocationStatus.denied,
            'Location access was not granted. You can enter the merchant manually.',
          ),
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
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

  Future<bool> openSettings() => Geolocator.openAppSettings();
}
