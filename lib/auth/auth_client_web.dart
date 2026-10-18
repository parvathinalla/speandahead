import 'package:auth0_flutter/auth0_flutter_web.dart';

import 'auth_client.dart';
import 'auth_config.dart';
import 'auth_profile.dart';

AuthClient createAuthClient() => WebAuthClient();

class WebAuthClient implements AuthClient {
  // Keep exactly one SPA client, including across callback handling.
  static final Auth0Web _sdk = Auth0Web(
    AuthConfig.domain, AuthConfig.webClientId,
    redirectUrl: AuthConfig.webRedirect,
  );
  static const _scopes = {'openid', 'profile', 'email'};

  AuthProfile _profile(dynamic credentials) {
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
    final credentials = await _sdk.onLoad(
      audience: AuthConfig.audience,
      scopes: _scopes,
      useRefreshTokens: false,
    );
    if (credentials == null) return null;
    return _profile(credentials);
  }

  @override
  Future<AuthProfile?> login() async {
    // Redirect to hosted Universal Login using PKCE and validated OAuth state.
    await _sdk.loginWithRedirect(
      audience: AuthConfig.audience,
      redirectUrl: AuthConfig.webRedirect,
      scopes: _scopes,
      parameters: const {},
    );
    // A successful login triggers a browser navigation; bootstrap resumes on return.
    return null;
  }

  @override
  Future<String?> accessToken() async {
    final creds = await _sdk.credentials(
      audience: AuthConfig.audience, scopes: _scopes,
    );
    return creds.accessToken;
  }

  @override
  Future<void> logout() => _sdk.logout(returnToUrl: AuthConfig.webRedirect);
}
