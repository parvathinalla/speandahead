import 'package:auth0_flutter/auth0_flutter.dart';

import 'auth_client.dart';
import 'auth_config.dart';
import 'auth_profile.dart';

AuthClient createAuthClient() => NativeAuthClient();

class NativeAuthClient implements AuthClient {
  final Auth0 _sdk = Auth0(AuthConfig.domain, AuthConfig.nativeClientId);
  static const _scopes = {'openid', 'profile', 'email', 'offline_access'};

  AuthProfile _profile(Credentials credentials) {
    final user = credentials.user;
    return AuthProfile(
      subject: user.sub,
      displayName: user.name ?? user.nickname ?? user.email ?? 'Member',
      email: user.email,
      photoUrl: user.pictureUrl?.toString(),
    );
  }

  @override
  Future<AuthProfile?> restore() async {
    if (!await _sdk.credentialsManager.hasValidCredentials()) return null;
    final creds = await _sdk.credentialsManager.credentials(minTtl: 90);
    return _profile(creds);
  }

  @override
  Future<AuthProfile?> login({required bool signUp}) async {
    final creds = await _sdk.webAuthentication(
      scheme: AuthConfig.customScheme,
    ).login(
      audience: AuthConfig.audience,
      scopes: _scopes,
      parameters: signUp ? {'screen_hint': 'signup'} : const {},
    );
    return _profile(creds);
  }

  @override
  Future<String?> accessToken() async {
    // Native SDK credentials manager renews expiring credentials securely.
    final credentials = await _sdk.credentialsManager.credentials(minTtl: 60);
    return credentials.accessToken;
  }

  @override
  Future<void> logout() async {
    try {
      await _sdk.webAuthentication(scheme: AuthConfig.customScheme).logout();
    } finally {
      await _sdk.credentialsManager.clearCredentials();
    }
  }
}
