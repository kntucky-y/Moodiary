import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  String? _cachedToken;
  String? _cachedUserId;

  Future<String?> readToken() async {
    final cached = _cachedToken;
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }
    final token = await _secure.read(key: _tokenKey);
    if (token != null && token.trim().isNotEmpty) {
      _cachedToken = token.trim();
      return _cachedToken;
    }
    return _migrateLegacyToken();
  }

  Future<String?> readUserId() async {
    final cached = _cachedUserId;
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }
    final userId = await _secure.read(key: _userIdKey);
    if (userId != null && userId.trim().isNotEmpty) {
      _cachedUserId = userId.trim();
      return _cachedUserId;
    }
    return _migrateLegacyUserId();
  }

  Future<void> setToken(String token) async {
    if (token.trim().isEmpty) return;
    final trimmed = token.trim();
    _cachedToken = trimmed;
    await _secure.write(key: _tokenKey, value: trimmed);
    await _removeLegacyToken();
  }

  Future<void> setUserId(String userId) async {
    if (userId.trim().isEmpty) return;
    final trimmed = userId.trim();
    _cachedUserId = trimmed;
    await _secure.write(key: _userIdKey, value: trimmed);
    await _removeLegacyUserId();
  }

  Future<void> clearSession() async {
    _cachedToken = null;
    _cachedUserId = null;
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _userIdKey);
    await _removeLegacyToken();
    await _removeLegacyUserId();
  }

  Future<String?> _migrateLegacyToken() async {
    if (kIsWeb) {
      final legacy = await _readLegacyToken();
      _cachedToken = legacy?.trim();
      return _cachedToken;
    }
    final legacy = await _readLegacyToken();
    if (legacy == null || legacy.trim().isEmpty) return null;
    final trimmed = legacy.trim();
    _cachedToken = trimmed;
    await _secure.write(key: _tokenKey, value: trimmed);
    await _removeLegacyToken();
    return trimmed;
  }

  Future<String?> _migrateLegacyUserId() async {
    if (kIsWeb) {
      final legacy = await _readLegacyUserId();
      _cachedUserId = legacy?.trim();
      return _cachedUserId;
    }
    final legacy = await _readLegacyUserId();
    if (legacy == null || legacy.trim().isEmpty) return null;
    final trimmed = legacy.trim();
    _cachedUserId = trimmed;
    await _secure.write(key: _userIdKey, value: trimmed);
    await _removeLegacyUserId();
    return trimmed;
  }

  Future<String?> _readLegacyToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<String?> _readLegacyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? prefs.getString('userId');
  }

  Future<void> _removeLegacyToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  Future<void> _removeLegacyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('userId');
  }
}
