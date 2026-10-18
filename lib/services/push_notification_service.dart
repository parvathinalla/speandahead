import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Registers this signed-in phone with FCM and reports notification taps.
/// Web builds intentionally skip this service; the product requirement is a
/// phone notification delivered by the installed Android/iOS application.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _cashflowOpens = StreamController<void>.broadcast();
  Stream<void> get cashflowOpens => _cashflowOpens.stream;

  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenSubscription;
  String? _registeredToken;
  bool _pendingCashflowOpen = false;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  Future<void> initialize() async {
    if (!_supported) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _messaging = FirebaseMessaging.instance;
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      final initial = await _messaging!.getInitialMessage();
      if (initial != null) _handleOpen(initial);
    } catch (error) {
      debugPrint('Push notifications unavailable: $error');
    }
  }

  Future<void> registerSignedInDevice() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _register(token);
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((freshToken) {
        _register(freshToken);
      });
    } catch (error) {
      debugPrint('Could not register push notifications: $error');
    }
  }

  Future<void> _register(String token) async {
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    await ApiService.registerPushDevice(token: token, platform: platform);
    _registeredToken = token;
  }

  Future<void> unregisterSignedInDevice() async {
    final token = _registeredToken;
    if (token == null) return;
    try {
      final platform =
          defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await ApiService.unregisterPushDevice(token: token, platform: platform);
    } catch (_) {
      // Signing out locally must still succeed if the backend is unavailable.
    } finally {
      _registeredToken = null;
      await _tokenSubscription?.cancel();
      _tokenSubscription = null;
    }
  }

  void _handleOpen(RemoteMessage message) {
    if (message.data['screen'] != 'cashflow') return;
    if (_cashflowOpens.hasListener) {
      _cashflowOpens.add(null);
    } else {
      _pendingCashflowOpen = true;
    }
  }

  bool takePendingCashflowOpen() {
    final pending = _pendingCashflowOpen;
    _pendingCashflowOpen = false;
    return pending;
  }
}
