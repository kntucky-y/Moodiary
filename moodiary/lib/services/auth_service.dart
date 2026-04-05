import 'dart:convert';
import 'dart:async';

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
  static const Duration _requestTimeout = Duration(seconds: 15);

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
    String? mbtiLatestType,
    String? currentPassword,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (mbtiLatestType != null) body['mbtiLatestType'] = mbtiLatestType;
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
    required String authToken,
    int limit = 20,
    int offset = 0,
  }) async {
    final encodedQuery = Uri.encodeQueryComponent(query);
    final uri = Uri.parse(
      '$kBackendBaseUrl/api/users/search/query?query=$encodedQuery&limit=$limit&offset=$offset',
    );
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
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

  Future<List<Map<String, dynamic>>> getSuggestedUsers({
    required String authToken,
    int limit = 10,
  }) async {
    final uri = Uri.parse(
      '$kBackendBaseUrl/api/users/search/suggested?limit=$limit',
    );
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final results = decoded['results'] as List?;
        return results?.cast<Map<String, dynamic>>() ?? [];
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load suggestions',
      );
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

  Future<void> sendFriendRequest({
    required String authToken,
    required String email,
  }) async {
    await _sendAuthedJson(
      '/api/friends/request',
      authToken: authToken,
      method: 'POST',
      body: {'email': email},
    );
  }

  Future<Set<String>> getConnectedUserIds({required String authToken}) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/friends');
    try {
      final response = await _client
          .get(uri, headers: {'Authorization': 'Bearer $authToken'})
          .timeout(_requestTimeout);

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(decoded['error']?.toString() ?? 'Request failed');
      }

      final connected = <String>{};
      final friends = decoded['friends'] as List<dynamic>? ?? const [];
      for (final item in friends) {
        final map = item as Map<String, dynamic>;
        final friend = map['friend'] as Map<String, dynamic>?;
        final id = (friend?['id'] ?? friend?['_id'])?.toString() ?? '';
        if (id.isNotEmpty) connected.add(id);
      }

      final pending = decoded['pending'] as Map<String, dynamic>? ?? const {};
      final incoming = pending['incoming'] as List<dynamic>? ?? const [];
      final outgoing = pending['outgoing'] as List<dynamic>? ?? const [];
      for (final item in [...incoming, ...outgoing]) {
        final map = item as Map<String, dynamic>;
        final friend = map['friend'] as Map<String, dynamic>?;
        final id = (friend?['id'] ?? friend?['_id'])?.toString() ?? '';
        if (id.isNotEmpty) connected.add(id);
      }

      return connected;
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      if (error is TimeoutException) {
        throw AuthException('Request timed out. Please try again.');
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<void> reportUser({
    required String authToken,
    required String targetUserId,
    required String reason,
    String details = '',
  }) async {
    await _sendAuthedJson(
      '/api/users/$targetUserId/report',
      authToken: authToken,
      method: 'POST',
      body: {
        'reason': reason,
        if (details.trim().isNotEmpty) 'details': details.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> submitMbtiTest({
    required String userId,
    required String authToken,
    required List<int> answers,
  }) async {
    return _sendAuthedJsonWithResponse(
      '/api/users/$userId/mbti/submit',
      authToken: authToken,
      method: 'POST',
      body: {'answers': answers},
    );
  }

  Future<Map<String, dynamic>> getMbtiHistory({
    required String userId,
    required String authToken,
    int limit = 10,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      '$kBackendBaseUrl/api/users/$userId/mbti/history?limit=$limit&offset=$offset',
    );
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final items = (decoded['items'] as List<dynamic>? ?? const []);
        return {...decoded, 'items': items.cast<Map<String, dynamic>>()};
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load MBTI history',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<void> unblockUser({
    required String userId,
    required String authToken,
    required String targetUserId,
  }) async {
    await _sendAuthedJson(
      '/api/users/$userId/unblock',
      authToken: authToken,
      method: 'POST',
      body: {'targetUserId': targetUserId},
    );
  }

  Future<void> muteUser({
    required String userId,
    required String authToken,
    required String targetUserId,
  }) async {
    await _sendAuthedJson(
      '/api/users/$userId/mute',
      authToken: authToken,
      method: 'POST',
      body: {'targetUserId': targetUserId},
    );
  }

  Future<void> unmuteUser({
    required String userId,
    required String authToken,
    required String targetUserId,
  }) async {
    await _sendAuthedJson(
      '/api/users/$userId/unmute',
      authToken: authToken,
      method: 'POST',
      body: {'targetUserId': targetUserId},
    );
  }

  Future<List<Map<String, dynamic>>> getBlockedUsers({
    required String userId,
    required String authToken,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/users/$userId/blocked');
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final users = decoded['blockedUsers'] as List<dynamic>? ?? const [];
        return users.cast<Map<String, dynamic>>();
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load blocked users',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<List<Map<String, dynamic>>> getMutedUsers({
    required String userId,
    required String authToken,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/users/$userId/muted');
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final users = decoded['mutedUsers'] as List<dynamic>? ?? const [];
        return users.cast<Map<String, dynamic>>();
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load muted users',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<Map<String, dynamic>> getNotifications({
    required String authToken,
    int limit = 20,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final unreadParam = unreadOnly ? 'true' : 'false';
    final uri = Uri.parse(
      '$kBackendBaseUrl/api/notifications?limit=$limit&offset=$offset&unread=$unreadParam',
    );
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final rawItems = (decoded['items'] as List<dynamic>? ?? const []);
        return {...decoded, 'items': rawItems.cast<Map<String, dynamic>>()};
      }

      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load notifications',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<void> markNotificationRead({
    required String authToken,
    required String notificationId,
  }) async {
    await _sendAuthedJson(
      '/api/notifications/$notificationId/read',
      authToken: authToken,
      method: 'POST',
      body: const {},
    );
  }

  Future<void> markAllNotificationsRead({required String authToken}) async {
    await _sendAuthedJson(
      '/api/notifications/read-all',
      authToken: authToken,
      method: 'POST',
      body: const {},
    );
  }

  Future<void> deleteNotification({
    required String authToken,
    required String notificationId,
  }) async {
    await _sendAuthedJson(
      '/api/notifications/$notificationId',
      authToken: authToken,
      method: 'DELETE',
      body: const {},
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

  Future<List<Map<String, dynamic>>> getMyJournalEntries({
    required String authToken,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/journal');
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded.cast<Map<String, dynamic>>();
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load journals',
      );
    } catch (error) {
      if (error is AuthException) {
        rethrow;
      }
      throw AuthException('Cannot reach the server. Please try again.');
    }
  }

  Future<List<Map<String, dynamic>>> getMyForumPosts({
    required String authToken,
    String? userName,
  }) async {
    final uri = Uri.parse('$kBackendBaseUrl/api/forums');
    try {
      final response = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $authToken'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded
            .cast<Map<String, dynamic>>()
            .where((post) => post['isMine'] == true)
            .toList();
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(
        decoded['error']?.toString() ?? 'Failed to load posts',
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
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

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
      if (error is TimeoutException) {
        throw AuthException('Request timed out. Please try again.');
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
