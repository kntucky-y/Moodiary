import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'local_notifications_service.dart';
import '../utils/in_app_notifications.dart';

class RealtimeNotifications {
  RealtimeNotifications._();

  static final RealtimeNotifications instance = RealtimeNotifications._();
  static const _kBaseUrl = 'https://moodiary-production.up.railway.app';

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;
  String? _token;
  bool _connecting = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Future<void> ensureConnected({String? token}) async {
    final resolvedToken = token ?? _token ?? await _loadToken();
    if (resolvedToken == null) {
      disconnect();
      return;
    }
    if (_socket != null && _socket!.connected && resolvedToken == _token) {
      return;
    }
    _token = resolvedToken;
    await _connect();
  }

  Future<void> _connect() async {
    if (_connecting) return;
    _connecting = true;
    try {
      _socket?.dispose();
      _socket = io.io(
        _kBaseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': _token})
            .disableAutoConnect()
            .build(),
      );
      _socket!
        ..connect()
        ..on('notifications:new', _handleNotification)
        ..onError((err) => _notifyConnectionIssue(err.toString()))
        ..onConnectError((err) => _notifyConnectionIssue(err.toString()));
    } finally {
      _connecting = false;
    }
  }

  Future<String?> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  void _handleNotification(dynamic data) {
    if (data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final type = payload['type'] as String? ?? 'update';
    final title = payload['title'] as String? ?? _titleFor(type, payload);
    final message =
        payload['message'] as String? ??
        payload['text'] as String? ??
        'You have a new update.';
    final icon = _iconFor(type);
    InAppNotifications.instance.show(
      title: title,
      message: message,
      icon: icon,
    );
    LocalNotificationsService.instance.showInstant(
      title: title,
      message: message,
    );
    _controller.add(payload);
  }

  String _titleFor(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'friend_message':
        final from = payload['from'];
        if (from is Map && from['name'] is String) {
          return '${from['name']} sent a message';
        }
        return 'New message from your friend';
      case 'friend_removed':
        return 'Friendship ended';
      default:
        return 'Moodiary update';
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'friend_message':
        return Icons.chat_bubble_outline;
      case 'friend_removed':
        return Icons.person_remove_alt_1;
      default:
        return Icons.notifications;
    }
  }

  void _notifyConnectionIssue(String? error) {
    final copy = (error == null || error.isEmpty)
        ? 'Realtime notifications are temporarily unavailable.'
        : error;
    InAppNotifications.instance.show(
      title: 'Notifications paused',
      message: copy,
      icon: Icons.wifi_off,
    );
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _token = null;
  }
}
