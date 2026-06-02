import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  SessionStore._();

  static final SessionStore instance = SessionStore._();

  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<String?> readToken() async {
    final token = await _secure.read(key: _tokenKey);
    if (token != null && token.trim().isNotEmpty) {
      return token.trim();
    }
    return _migrateLegacyToken();
  }

  Future<String?> readUserId() async {
    final userId = await _secure.read(key: _userIdKey);
    if (userId != null && userId.trim().isNotEmpty) {
      return userId.trim();
    }
    return _migrateLegacyUserId();
  }

  Future<void> setToken(String token) async {
    if (token.trim().isEmpty) return;
    await _secure.write(key: _tokenKey, value: token.trim());
    await _removeLegacyToken();
  }

  Future<void> setUserId(String userId) async {
    if (userId.trim().isEmpty) return;
    await _secure.write(key: _userIdKey, value: userId.trim());
    await _removeLegacyUserId();
  }

  Future<void> clearSession() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _userIdKey);
    await _removeLegacyToken();
    await _removeLegacyUserId();
  }

  Future<String?> _migrateLegacyToken() async {
    if (kIsWeb) {
      return _readLegacyToken();
    }
    final legacy = await _readLegacyToken();
    if (legacy == null || legacy.trim().isEmpty) return null;
    await _secure.write(key: _tokenKey, value: legacy.trim());
    await _removeLegacyToken();
    return legacy.trim();
  }

  Future<String?> _migrateLegacyUserId() async {
    if (kIsWeb) {
      return _readLegacyUserId();
    }
    final legacy = await _readLegacyUserId();
    if (legacy == null || legacy.trim().isEmpty) return null;
    await _secure.write(key: _userIdKey, value: legacy.trim());
    await _removeLegacyUserId();
    return legacy.trim();
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
