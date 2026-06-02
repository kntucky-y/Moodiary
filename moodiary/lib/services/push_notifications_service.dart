import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'session_store.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // If Firebase is not configured on this build, skip background setup.
  }
}

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;
  bool _firebaseReady = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      _firebaseReady = false;
      _initialized = true;
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    _initialized = true;
    unawaited(messaging.setAutoInitEnabled(true));
    unawaited(
      messaging.requestPermission(alert: true, badge: true, sound: true),
    );

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      unawaited(_registerTokenWithStoredSession(token));
    });

    unawaited(
      messaging
          .getToken()
          .then((token) {
            if (token != null && token.isNotEmpty) {
              return _registerTokenWithStoredSession(token);
            }
          })
          .catchError((_) {}),
    );
  }

  Future<void> syncWithAuthToken(String authToken) async {
    if (!_firebaseReady) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await AuthService.instance.registerPushToken(
      authToken: authToken,
      pushToken: token,
    );
  }

  Future<void> unregisterWithAuthToken(String authToken) async {
    if (!_firebaseReady) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await AuthService.instance.removePushToken(
      authToken: authToken,
      pushToken: token,
    );
  }

  Future<void> _registerTokenWithStoredSession(String token) async {
    final authToken = await SessionStore.instance.readToken();
    if (authToken == null || authToken.isEmpty) return;
    try {
      await AuthService.instance.registerPushToken(
        authToken: authToken,
        pushToken: token,
      );
    } catch (_) {
      // Fail silently to avoid disrupting app flow on temporary network issues.
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
  }
}
