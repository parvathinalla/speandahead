import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/push_notification_service.dart';
import 'auth_client.dart';
import 'auth_client_factory.dart';
import 'auth_config.dart';
import 'auth_profile.dart';

/// One session controller for the whole app. Auth0 tokens are fetched from the
/// SDK immediately before API calls. Never store tokens in shared preferences.
class AuthSession extends ChangeNotifier {
  AuthSession._();
  static final AuthSession instance = AuthSession._();

  AuthClient? _client;
  AuthProfile? _profile;
  bool _started = false;
  bool _initializing = true;
  bool _busy = false;
  bool _checkingLink = false;
  bool _sandboxLinked = false;
  bool _hasJointAccount = false;
  String? _error;
  String? _configError;
  String _loadingMessage = 'Restoring secure sign-in…';

  AuthProfile? get profile => _profile;
  bool get signedIn => _profile != null;
  bool get initializing => _initializing;
  bool get busy => _busy || _checkingLink;
  bool get sandboxLinked => _sandboxLinked;
  bool get hasJointAccount => _hasJointAccount;
  String? get error => _error;
  String? get configurationError => _configError;
  String get loadingMessage => _loadingMessage;

  Future<void> bootstrap() async {
    if (_started) return;
    _started = true;
    notifyListeners();
    try {
      if (AuthConfig.debugDemo) {
        _profile = const AuthProfile(
          subject: 'demo-sarah',
          displayName: 'Demo Member',
          email: 'demo@example.invalid',
        );
        ApiService.tokenProvider = null;
        await refreshLink();
      } else if (!AuthConfig.isConfigured) {
        _configError = AuthConfig.missingConfiguration;
      } else {
        _client = createAuthClient();
        ApiService.tokenProvider = _client!.accessToken;
        final watch = Stopwatch()..start();
        _profile = await _client!.restore();
        if (!kReleaseMode) debugPrint('Auth timing: SDK restore ${watch.elapsedMilliseconds}ms');
        if (_profile != null) {
          _loadingMessage = 'Loading your accounts…';
          notifyListeners();
          await refreshLink();
        }
      }
    } catch (exception) {
      _error = 'Unable to restore secure session. ' + exception.toString();
      _profile = null;
      _sandboxLinked = false;
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> refreshLink() async {
    if (_profile == null || _checkingLink) return;
    _checkingLink = true;
    notifyListeners();
    try {
      final watch = Stopwatch()..start();
      final results = await Future.wait([
        ApiService.me(), ApiService.jointMembership(),
      ]);
      final me = results[0];
      if (!AuthConfig.debugDemo && me['security_mode'] != 'auth0') {
        throw ApiException(
            'FastAPI must use AUTH_MODE=auth0 before using real user logins.');
      }
      _sandboxLinked = me['sandbox_linked'] == true;
      final joint = results[1];
      _hasJointAccount = joint['has_joint_account'] == true;
      if (!kReleaseMode) debugPrint('Auth timing: account loading ${watch.elapsedMilliseconds}ms');
      _error = null;
      await PushNotificationService.instance.registerSignedInDevice();
    } catch (error) {
      _sandboxLinked = false;
      _hasJointAccount = false;
      _error = error.toString();
    } finally {
      _checkingLink = false;
    }
    notifyListeners();
  }

  Future<void> signIn() async {
    if (_busy || _configError != null) return;
    if (AuthConfig.debugDemo) {
      _profile ??= const AuthProfile(
        subject: 'demo-sarah',
        displayName: 'Demo Member',
        email: 'demo@example.invalid',
      );
      ApiService.tokenProvider = null;
      await refreshLink();
      return;
    }
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _client ??= createAuthClient();
      ApiService.tokenProvider = _client!.accessToken;
      final identity = await _client!.login();
      if (identity != null) {
        _profile = identity;
        await refreshLink();
      }
      // Web login redirects to Auth0; it cannot return a profile until onLoad.
    } catch (error) {
      _error = 'Sign-in unsuccessful. Please try again. ' + error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    if (_busy) return;
    _busy = true;
    await PushNotificationService.instance.unregisterSignedInDevice();
    // Erase user-specific visible state and bearer-token source immediately.
    _profile = null;
    _sandboxLinked = false;
    _hasJointAccount = false;
    _error = null;
    ApiService.tokenProvider = null;
    notifyListeners();
    try {
      if (!AuthConfig.debugDemo) {
        await _client?.logout();
      }
    } catch (_) {
      // Stay signed out locally even if the remote session logout fails.
      _error = 'Signed out in this app. Auth0 logout was not confirmed.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
