import 'package:shared_preferences/shared_preferences.dart';

import 'streak_utils.dart';

/// Centralized helpers for clearing state that should be scoped to a
/// particular authenticated user.
class UserCache {
  static const profileBundleCacheKey = 'user_profile_bundle_cache';

  static const _scopedKeys = <String>{
    'tasks_date',
    'tasks_indices',
    'tasks_completed',
    'tasks_ai_payload',
    'mood_logs_cache',
    'home_ai_insights_cache',
    'home_ai_insights_cache_ts',
    'home_journal_preview_cache',
    'home_journal_preview_cache_ts',
    'forums_cache_v1',
    'friends_cache_v1',
    'companion_id',
    'companion_name',
    'user_avatar_url',
    profileBundleCacheKey,
    StreakUtils.streakCountKey,
    StreakUtils.streakLastDateKey,
  };

  static Future<void> clear([SharedPreferences? prefs]) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    for (final key in _scopedKeys) {
      await instance.remove(key);
    }
    final moodScoreKeys = instance
        .getKeys()
        .where((key) => key.startsWith('mood_score_'))
        .toList();
    for (final key in moodScoreKeys) {
      await instance.remove(key);
    }
  }
}
