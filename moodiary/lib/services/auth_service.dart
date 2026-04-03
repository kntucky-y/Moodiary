import 'dart:convert';

import 'package:http/http.dart' as http;

const String kBackendBaseUrl = 'https://moodiary-production.up.railway.app';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return _postJson(
      '/api/auth/login',
      body: {'email': email, 'password': password},
    );
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return _postJson(
      '/api/auth/register',
      body: {'name': name, 'email': email, 'password': password},
    );
  }

  Future<String> requestPasswordReset({required String email}) async {
    final response = await _postJson(
      '/api/auth/forgot-password',
      body: {'email': email},
    );
    return response['message'] as String? ??
        'If that email exists, a reset link has been sent';
  }

  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String password,
  }) async {
    return _postJson(
      '/api/auth/reset-password',
      body: {'token': token, 'password': password},
    );
  }

  Future<void> registerPushToken({
    required String authToken,
    required String pushToken,
  }) async {
    await _sendAuthedJson(
      '/api/auth/push-token',
      authToken: authToken,
      method: 'POST',
      body: {'token': pushToken},
    );
  }

  Future<void> removePushToken({
    required String authToken,
    required String pushToken,
  }) async {
    await _sendAuthedJson(
      '/api/auth/push-token',
      authToken: authToken,
      method: 'DELETE',
      body: {'token': pushToken},
    );
  }

  // Profile Management

  Future<Map<String, dynamic>> getUserProfile({required String userId}) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/users/profile/$userId');
    try {
      final response = await _client.get(uri);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to fetch profile',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String userId,
    required String authToken,
    String? name,
    String? email,
    String? bio,
    String? avatarUrl,
    String? currentPassword,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (currentPassword != null) body['currentPassword'] = currentPassword;
    if (newPassword != null) body['newPassword'] = newPassword;

    return _sendAuthedJsonWithResponse(
      '/api/users/$userId',
      authToken: authToken,
      method: 'PATCH',
      body: body,
    );
  }

  Future<void> deleteAccount({
    required String userId,
    required String authToken,
    required String password,
  }) async {
    await _sendAuthedJson(
      '/api/users/$userId',
      authToken: authToken,
      method: 'DELETE',
      body: {'password': password},
    );
  }

  Future<List<Map<String, dynamic>>> searchUsers({
    required String query,
  }) async {
    final uri = Uri.parse(
      '$kBackendBaseUrl/api/users/search/query?query=$query',
    );
    try {
      final response = await _client.get(uri);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final results = decoded['results'] as List?;
        return results?.cast<Map<String, dynamic>>() ?? [];
      }

      throw AuthException(decoded['error']?.toString() ?? 'Search failed');
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<void> blockUser({
    required String userId,
    required String authToken,
    required String targetUserId,
  }) async {
    await _sendAuthedJson(
      '/api/users/$userId/block',
      authToken: authToken,
      method: 'POST',
      body: {'targetUserId': targetUserId},
    );
  }

  Future<Map<String, dynamic>> getResources({String? category}) async {
    final uri = category != null
        ? Uri.parse('$kBackendBaseUrl/api/resources?category=$category')
        : Uri.parse('$kBackendBaseUrl/api/resources');
    try {
      final response = await _client.get(uri);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to fetch resources',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl$path');

    try {
      final response = await _client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Authentication failed',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<void> _sendAuthedJson(
    String path, {
    required String authToken,
    required String method,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl$path');
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      };
      final encodedBody = jsonEncode(body);
      late final http.Response response;
      if (method == 'POST') {
        response = await _client.post(uri, headers: headers, body: encodedBody);
      } else if (method == 'PATCH') {
        response = await _client.patch(
          uri,
          headers: headers,
          body: encodedBody,
        );
      } else {
        response = await _client.delete(
          uri,
          headers: headers,
          body: encodedBody,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(decoded['error']?.toString() ?? 'Request failed');
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<Map<String, dynamic>> _sendAuthedJsonWithResponse(
    String path, {
    required String authToken,
    required String method,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl$path');
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      };
      final encodedBody = jsonEncode(body);
      late final http.Response response;
      if (method == 'POST') {
        response = await _client.post(uri, headers: headers, body: encodedBody);
      } else if (method == 'PATCH') {
        response = await _client.patch(
          uri,
          headers: headers,
          body: encodedBody,
        );
      } else {
        response = await _client.delete(
          uri,
          headers: headers,
          body: encodedBody,
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      throw AuthException(decoded['error']?.toString() ?? 'Request failed');
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  void dispose() {
    _client.close();
  }
}
