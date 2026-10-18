import 'package:flutter/foundation.dart';

/// These are PUBLIC OAuth client identifiers, never an Auth0 client secret.
class AuthConfig {
  static const domain = String.fromEnvironment('AUTH0_DOMAIN');
  static const webClientId = String.fromEnvironment('AUTH0_WEB_CLIENT_ID');
  static const nativeClientId = String.fromEnvironment('AUTH0_NATIVE_CLIENT_ID');
  static const audience = String.fromEnvironment('AUTH0_AUDIENCE');
  static const customScheme = 'creditpilot';
  static const explicitRedirect = String.fromEnvironment('AUTH0_REDIRECT_URI');

  static String get clientId => kIsWeb ? webClientId : nativeClientId;
  static String get webRedirect =>
      explicitRedirect.isNotEmpty ? explicitRedirect : Uri.base.origin;

  /// Only available in explicitly enabled Flutter DEBUG sessions. Never release.
  static const _demoRequested = bool.fromEnvironment('DEV_DEMO_AUTH', defaultValue: false);
  static bool get debugDemo => kDebugMode && _demoRequested;

  static bool get isConfigured =>
      domain.isNotEmpty && clientId.isNotEmpty && audience.isNotEmpty;

  static String get missingConfiguration =>
      'Set AUTH0_DOMAIN, AUTH0_AUDIENCE and ' +
      (kIsWeb ? 'AUTH0_WEB_CLIENT_ID' : 'AUTH0_NATIVE_CLIENT_ID') +
      ' using flutter --dart-define. No credentials should be stored in source.';
}
