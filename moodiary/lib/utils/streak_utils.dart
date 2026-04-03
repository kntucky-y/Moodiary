import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StreakUtils {
  static const streakCountKey = 'streak_count';
  static const streakLastDateKey = 'streak_last_date';

  static Future<int> refreshFromMoodCache([SharedPreferences? prefs]) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    final raw = instance.getString('mood_logs_cache');
    if (raw == null || raw.isEmpty) {
      await _store(instance, 0, null);
      return 0;
    }

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await _store(instance, 0, null);
      return 0;
    }

    final dateKeys = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final dateKey = map['dateKey']?.toString();
      if (dateKey == null || dateKey.isEmpty) continue;
      if (_hasProgress(map)) {
        dateKeys.add(dateKey);
      }
    }

    if (dateKeys.isEmpty) {
      await _store(instance, 0, null);
      return 0;
    }

    final sorted = dateKeys.toList()..sort((a, b) => b.compareTo(a));

    final latestKey = sorted.first;
    final latestDate = _parseDateKey(latestKey);
    if (latestDate == null) {
      await _store(instance, 0, null);
      return 0;
    }

    final today = _todayDate();
    final gapFromToday = today.difference(latestDate).inDays;
    if (gapFromToday > 1) {
      await _store(instance, 0, latestKey);
      return 0;
    }

    var streak = 1;
    var cursor = latestDate;
    while (true) {
      cursor = cursor.subtract(const Duration(days: 1));
      final prevKey = _dateKey(cursor);
      if (dateKeys.contains(prevKey)) {
        streak += 1;
      } else {
        break;
      }
    }

    await _store(instance, streak, latestKey);
    return streak;
  }

  static Future<int> getStored([SharedPreferences? prefs]) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    return instance.getInt(streakCountKey) ?? 0;
  }

  static bool _hasProgress(Map<String, dynamic> entry) {
    final moodLevel = entry['moodLevel'];
    if (moodLevel is int && moodLevel >= 1 && moodLevel <= 5) {
      return true;
    }

    final taskScore = entry['taskScore'];
    if (taskScore is num && taskScore > 0) {
      return true;
    }

    final activityScore = entry['activityScore'];
    if (activityScore is num && activityScore > 0) {
      return true;
    }

    final score = entry['score'];
    if (score is num && score > 0) {
      return true;
    }

    final activities = entry['activities'];
    if (activities is List && activities.isNotEmpty) {
      return true;
    }

    return false;
  }

  static DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static Future<void> _store(
    SharedPreferences prefs,
    int count,
    String? lastDate,
  ) async {
    await prefs.setInt(streakCountKey, count);
    if (lastDate == null || lastDate.isEmpty) {
      await prefs.remove(streakLastDateKey);
    } else {
      await prefs.setString(streakLastDateKey, lastDate);
    }
  }
}
