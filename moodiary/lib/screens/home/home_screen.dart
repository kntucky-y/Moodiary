import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../onboarding/onboarding_screen.dart';
import '../companion/companion_screen.dart';
import '../calendar/calendar_screen.dart';
import '../journal/journal_screen.dart';
import '../app_shell.dart';
import '../profile/user_profile_screen.dart';
import '../../services/local_notifications_service.dart';
import '../../services/auth_service.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/glass.dart';
import '../../services/realtime_notifications.dart';
import '../settings/settings_screen.dart';
import '../../utils/avatar_utils.dart';
import '../../utils/streak_utils.dart';

const _kPurple = Color(0xFFA076F9);

const _moods = [
  _Mood('Terrible', 'assets/terrible.png'),
  _Mood('Bad', 'assets/bad.png'),
  _Mood('Okay', 'assets/okay.png'),
  _Mood('Good', 'assets/good.png'),
  _Mood('Excellent', 'assets/excellent.png'),
];

// Must match calendar_screen.dart _moodLevelPoints
const _homeMoodLevelPoints = [5, 10, 20, 35, 50];

const _kAiInsightsCacheKey = 'home_ai_insights_cache';
const _kAiInsightsCacheTsKey = 'home_ai_insights_cache_ts';
const _kAiAnalysisCacheKey = 'home_ai_analysis_cache';
const _kAiAnalysisCacheTsKey = 'home_ai_analysis_cache_ts';
const _kJournalPreviewCacheKey = 'home_journal_preview_cache';
const _kJournalPreviewCacheTsKey = 'home_journal_preview_cache_ts';
const _kAiTasksCacheKey = 'tasks_ai_payload';
const _kAiInsightsCacheTtl = Duration(hours: 24);
const _kAiAnalysisCacheTtl = Duration(hours: 24);
const _kJournalPreviewCacheTtl = Duration(hours: 6);

class _MoodTask {
  final String id;
  final String title;
  final String description;
  final int points;
  final String? asset;
  final IconData? icon;
  final Color iconColor;
  final Color iconBackground;

  const _MoodTask({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    this.asset,
    this.icon,
    this.iconColor = _kPurple,
    this.iconBackground = const Color(0xFFF3F0FB),
  });
}

/// Fallback pool of universally helpful mood-lifting tasks.
/// Used when the AI backend returns no tasks (new user, insufficient data, error).
const _kFallbackTaskPool = [
  _MoodTask(
    id: 'fallback_walk',
    title: 'Take a 10-Minute Walk',
    description: 'A short walk can boost your mood and clear your mind.',
    points: 10,
    icon: Icons.directions_walk_rounded,
    iconColor: Color(0xFF10B981),
    iconBackground: Color(0xFFD1FAE5),
  ),
  _MoodTask(
    id: 'fallback_water',
    title: 'Drink a Glass of Water',
    description: 'Stay hydrated — it helps your energy and focus.',
    points: 5,
    icon: Icons.water_drop_rounded,
    iconColor: Color(0xFF3B82F6),
    iconBackground: Color(0xFFDBEAFE),
  ),
  _MoodTask(
    id: 'fallback_breathe',
    title: 'Deep Breathing Exercise',
    description: 'Take 5 slow, deep breaths to calm your nervous system.',
    points: 10,
    icon: Icons.air_rounded,
    iconColor: Color(0xFF8B5CF6),
    iconBackground: Color(0xFFEDE9FE),
  ),
  _MoodTask(
    id: 'fallback_gratitude',
    title: 'Write 3 Things You\'re Grateful For',
    description: 'Gratitude journaling is proven to improve well-being.',
    points: 10,
    icon: Icons.favorite_rounded,
    iconColor: Color(0xFFEC4899),
    iconBackground: Color(0xFFFCE7F3),
  ),
  _MoodTask(
    id: 'fallback_stretch',
    title: 'Do a Quick Stretch',
    description:
        'Stretch for 5 minutes to relieve tension and improve circulation.',
    points: 10,
    icon: Icons.self_improvement_rounded,
    iconColor: Color(0xFFF59E0B),
    iconBackground: Color(0xFFFEF3C7),
  ),
  _MoodTask(
    id: 'fallback_music',
    title: 'Listen to Your Favorite Song',
    description:
        'Music can instantly lift your spirits — put on a feel-good track.',
    points: 5,
    icon: Icons.music_note_rounded,
    iconColor: Color(0xFFE11D48),
    iconBackground: Color(0xFFFFE4E6),
  ),
  _MoodTask(
    id: 'fallback_tidy',
    title: 'Tidy Up Your Space',
    description:
        'A clean environment can reduce stress and boost productivity.',
    points: 10,
    icon: Icons.cleaning_services_rounded,
    iconColor: Color(0xFF0EA5E9),
    iconBackground: Color(0xFFE0F2FE),
  ),
  _MoodTask(
    id: 'fallback_connect',
    title: 'Reach Out to a Friend',
    description: 'Send a kind message to someone you care about.',
    points: 10,
    icon: Icons.chat_bubble_rounded,
    iconColor: Color(0xFF6366F1),
    iconBackground: Color(0xFFE0E7FF),
  ),
  _MoodTask(
    id: 'fallback_snack',
    title: 'Have a Healthy Snack',
    description: 'Fuel your body with something nutritious and delicious.',
    points: 5,
    icon: Icons.restaurant_rounded,
    iconColor: Color(0xFF22C55E),
    iconBackground: Color(0xFFDCFCE7),
  ),
  _MoodTask(
    id: 'fallback_journal',
    title: 'Write in Your Journal',
    description: 'Spend a few minutes writing about your day or feelings.',
    points: 15,
    icon: Icons.edit_note_rounded,
    iconColor: Color(0xFF7C3AED),
    iconBackground: Color(0xFFF3E8FF),
  ),
];

class _Mood {
  final String label;
  final String asset;
  const _Mood(this.label, this.asset);
}

class _BoosterSuggestion {
  final String activity;
  final String reason;
  const _BoosterSuggestion({required this.activity, required this.reason});

  factory _BoosterSuggestion.fromJson(Map<String, dynamic> j) {
    return _BoosterSuggestion(
      activity: (j['activity'] ?? '').toString(),
      reason: (j['reason'] ?? '').toString(),
    );
  }
}

class _MoodInsights {
  final List<int?> last7;
  final int trendPercent;
  final String trendDirection;
  final String aiMessage;
  final List<_BoosterSuggestion> boosters;
  final DateTime? generatedAt;

  const _MoodInsights({
    required this.last7,
    required this.trendPercent,
    required this.trendDirection,
    required this.aiMessage,
    required this.boosters,
    required this.generatedAt,
  });

  factory _MoodInsights.fromJson(Map<String, dynamic> j) {
    final rawLast7 = (j['last7'] as List<dynamic>? ?? const []);
    final last7 = rawLast7
        .map((v) => v is num ? v.toInt() : null)
        .toList(growable: false);
    final boosters = (j['boosters'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_BoosterSuggestion.fromJson)
        .toList();
    final generated = j['generatedAt']?.toString();
    return _MoodInsights(
      last7: last7,
      trendPercent: (j['trendPercent'] as num?)?.toInt() ?? 0,
      trendDirection: (j['trendDirection'] ?? 'steady').toString(),
      aiMessage: (j['aiMessage'] ?? '').toString(),
      boosters: boosters,
      generatedAt: generated != null && generated.isNotEmpty
          ? DateTime.tryParse(generated)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'last7': last7,
    'trendPercent': trendPercent,
    'trendDirection': trendDirection,
    'aiMessage': aiMessage,
    'boosters': boosters
        .map((b) => {'activity': b.activity, 'reason': b.reason})
        .toList(),
    'generatedAt': generatedAt?.toIso8601String(),
  };
}

class _AnalysisLink {
  final String title;
  final String url;

  const _AnalysisLink({required this.title, required this.url});

  factory _AnalysisLink.fromJson(Map<String, dynamic> j) {
    return _AnalysisLink(
      title: (j['title'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'url': url};
}

class _MoodAnalysis {
  final String detectedMood;
  final String scope;
  final List<_AnalysisLink> links;
  final DateTime? generatedAt;

  const _MoodAnalysis({
    required this.detectedMood,
    required this.scope,
    required this.links,
    required this.generatedAt,
  });

  factory _MoodAnalysis.fromJson(Map<String, dynamic> j) {
    final links = (j['links'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_AnalysisLink.fromJson)
        .toList();
    final generated = j['generatedAt']?.toString();
    return _MoodAnalysis(
      detectedMood: (j['detectedMood'] ?? '').toString(),
      scope: (j['scope'] ?? 'day').toString(),
      links: links,
      generatedAt: generated != null && generated.isNotEmpty
          ? DateTime.tryParse(generated)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'detectedMood': detectedMood,
    'scope': scope,
    'links': links.map((link) => link.toJson()).toList(),
    'generatedAt': generatedAt?.toIso8601String(),
  };
}

class _JournalPreview {
  final String title;
  final String content;
  final String tag;
  final DateTime createdAt;

  const _JournalPreview({
    required this.title,
    required this.content,
    required this.tag,
    required this.createdAt,
  });

  factory _JournalPreview.fromJson(Map<String, dynamic> j) {
    return _JournalPreview(
      title: (j['title'] ?? '').toString(),
      content: (j['content'] ?? '').toString(),
      tag: (j['tag'] ?? 'okay').toString(),
      createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'tag': tag,
    'createdAt': createdAt.toIso8601String(),
  };
}

class _MiniMoodDay {
  final String label;
  final int? score;
  const _MiniMoodDay({required this.label, required this.score});
}

class HomeScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final String? initialProfileAvatarUrl;
  final bool showBottomNav;
  final ShellTabSelector? onShellTabSelected;

  const HomeScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.initialProfileAvatarUrl,
    this.showBottomNav = true,
    this.onShellTabSelected,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int? _selectedMood;
  bool _sidebarOpen = false;
  bool _headerCollapsed = false;
  String? _profileAvatarUrl;
  ImageProvider<Object>? _profileAvatarImage;

  List<_MoodTask> _todayTasks = [];
  List<bool> _completedStates = [false, false, false];
  bool _tasksLoading = true; // true until AI tasks arrive or fallback used
  int _taskPoints = 0; // points from task completions only
  int _todayActivityScore = 0; // activity score from calendar log (today)
  int _moodScore = 0; // combined: taskPoints + moodLevelScore + activityScore
  int _streakCount = 0;

  _MoodInsights? _insights;
  bool _insightsLoading = true;
  String? _insightsError;

  _MoodAnalysis? _analysis;
  bool _analysisLoading = false;
  String? _analysisError;

  _JournalPreview? _journalPreview;
  bool _journalLoading = true;
  String? _journalError;

  List<_MiniMoodDay> _miniCalendarDays = const [];

  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    final initialAvatar = widget.initialProfileAvatarUrl?.trim();
    if (initialAvatar != null && initialAvatar.isNotEmpty) {
      _profileAvatarUrl = initialAvatar;
      _profileAvatarImage = avatarImageProvider(initialAvatar);
    }
    _loadProfileAvatar();
    _loadTodayTasks();
    _loadAiInsights();
    _loadMoodAnalysis();
    _loadJournalPreview();
    _loadMiniCalendarFromCache();
  }

  Future<void> _loadProfileAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final avatarUrl = prefs.getString('user_avatar_url');
    if (avatarUrl == _profileAvatarUrl) return;
    setState(() {
      _profileAvatarUrl = avatarUrl;
      _profileAvatarImage = avatarImageProvider(avatarUrl);
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed =
        notification.metrics.pixels > context.mdHeaderCollapseOffset;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
    return false;
  }

  String _dateKey() {
    return _toDateKey(DateTime.now());
  }

  String _toDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _looksLikeGoalText(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('daily goal') || lower.contains('weekly goal')) {
      return true;
    }
    if (lower.contains('streak')) return true;
    return RegExp(r'\breach\s+\d+').hasMatch(lower);
  }

  List<_MoodTask> _decodeAiTasks(List<dynamic>? raw) {
    if (raw == null) return [];
    final tasks = <_MoodTask>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final title = (map['title'] ?? '').toString().trim();
      final description = (map['description'] ?? '').toString().trim();
      final points = (map['points'] as num?)?.toInt() ?? 10;
      if (title.isEmpty || description.isEmpty) continue;
      if (_looksLikeGoalText(title) || _looksLikeGoalText(description)) {
        continue;
      }
      tasks.add(
        _MoodTask(
          id: title.toLowerCase().replaceAll(' ', '_'),
          title: title,
          description: description,
          points: points.clamp(5, 20),
          icon: Icons.auto_awesome_rounded,
          iconColor: const Color(0xFF6366F1),
          iconBackground: const Color(0xFFE0E7FF),
        ),
      );
    }
    return tasks;
  }

  bool _tasksMatch(List<_MoodTask> a, List<_MoodTask> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].title != b[i].title || a[i].points != b[i].points) {
        return false;
      }
    }
    return true;
  }

  /// Returns 3 deterministic fallback tasks for today (seeded by date).
  List<_MoodTask> _fallbackTasks() {
    final seed = _dateKey().hashCode;
    final pool = List<_MoodTask>.from(_kFallbackTaskPool);
    pool.shuffle(Random(seed));
    return pool.take(3).toList();
  }

  Future<void> _applyAiTasks(
    List<_MoodTask> tasks, {
    required bool resetProgress,
  }) async {
    if (tasks.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();

    if (resetProgress) {
      await prefs.setString('tasks_completed', 'false,false,false');
      await prefs.setInt('mood_score_$today', 0);
      await _upsertTaskProgressInMoodCache(today, 0);
      _syncScoreToDb(today, 0);
    }

    List<bool> completedStates = List<bool>.filled(tasks.length, false);
    if (!resetProgress) {
      final cStr = prefs.getString('tasks_completed') ?? 'false,false,false';
      final parsed = cStr.split(',').map((s) => s == 'true').toList();
      if (parsed.length == tasks.length) {
        completedStates = parsed;
      }
    }

    await prefs.setString(
      _kAiTasksCacheKey,
      jsonEncode(
        tasks
            .map(
              (t) => {
                'title': t.title,
                'description': t.description,
                'points': t.points,
              },
            )
            .toList(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _todayTasks = tasks;
      _completedStates = completedStates;
      _tasksLoading = false;
      if (resetProgress) {
        _taskPoints = 0;
        _moodScore =
            _todayActivityScore +
            (_selectedMood == null ? 0 : _homeMoodLevelPoints[_selectedMood!]);
      }
    });
  }

  Future<void> _refreshAfterMoodUpdate() async {
    await _loadMiniCalendarFromCache();
    await _fetchAiInsights();
  }

  /// Loads today's tasks from cache. If AI tasks are cached, use them.
  /// Otherwise, keep _tasksLoading=true so the UI shows a loading indicator
  /// until _loadAiInsights / _fetchAiInsights provides AI tasks.
  Future<void> _loadTodayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final savedDate = prefs.getString('tasks_date');

    List<bool> completed;

    if (savedDate != today) {
      await prefs.setString('tasks_date', today);
      await prefs.setString('tasks_completed', 'false,false,false');
      await prefs.setInt('mood_score_$today', 0);
      completed = [false, false, false];
    } else {
      final cStr = prefs.getString('tasks_completed') ?? 'false,false,false';
      completed = cStr.split(',').map((s) => s == 'true').toList();
    }

    List<_MoodTask> tasks = [];
    final rawTasks = prefs.getString(_kAiTasksCacheKey);
    if (rawTasks != null) {
      try {
        final decoded = jsonDecode(rawTasks) as List<dynamic>;
        tasks = _decodeAiTasks(decoded);
      } catch (_) {}
    }

    // If no cached AI tasks, use fallback mood-lifting tasks immediately.
    if (tasks.isEmpty) {
      tasks = _fallbackTasks();
    }

    if (completed.length != tasks.length) {
      completed = List<bool>.filled(tasks.length, false);
    }

    final taskPoints = prefs.getInt('mood_score_$today') ?? 0;
    // Read today's mood/activity score from the shared calendar cache
    int moodActivityScore = 0;
    int activityScore = 0;
    int? cachedMoodLevel;
    final cached = prefs.getString('mood_logs_cache');
    if (cached != null) {
      try {
        final List<dynamic> data = jsonDecode(cached);
        final entry = data.firstWhere(
          (d) => d['dateKey'] == today,
          orElse: () => null,
        );
        if (entry != null) {
          moodActivityScore = (entry['moodScore'] ?? 0) as int;
          activityScore = (entry['activityScore'] ?? 0) as int;
          final ml = entry['moodLevel'];
          if (ml != null && (ml as int) >= 1 && ml <= 5) cachedMoodLevel = ml;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _todayTasks = tasks;
        _completedStates = completed;
        _tasksLoading = false;
        _taskPoints = taskPoints;
        _todayActivityScore = activityScore;
        _moodScore = taskPoints + moodActivityScore;
        // Pre-select mood icon if today's log already has one
        if (cachedMoodLevel != null) _selectedMood = cachedMoodLevel - 1;
      });
      await _refreshStreak();
      _entranceCtrl.forward(from: 0);
    }
  }

  Future<void> _loadAiInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAiInsightsCacheKey);
    final ts = prefs.getInt(_kAiInsightsCacheTsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final cachedTasks = _decodeAiTasks(decoded['tasks'] as List<dynamic>?);
        if (cachedTasks.isNotEmpty && !_tasksMatch(_todayTasks, cachedTasks)) {
          await _applyAiTasks(cachedTasks, resetProgress: false);
        }
        if (mounted) {
          setState(() {
            _insights = _MoodInsights.fromJson(decoded);
            _insightsLoading = false;
          });
        }
      } catch (_) {}
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isFresh =
        ts != null && nowMs - ts < _kAiInsightsCacheTtl.inMilliseconds;
    if (isFresh) {
      // Ensure tasks are never empty — apply fallback if needed
      if (_todayTasks.isEmpty && mounted) {
        await _applyAiTasks(_fallbackTasks(), resetProgress: false);
      }
      return;
    }
    await _fetchAiInsights();
  }

  Future<void> _fetchAiInsights() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (_todayTasks.isEmpty) {
        await _applyAiTasks(_fallbackTasks(), resetProgress: false);
      }
      if (mounted) {
        setState(() {
          _insightsLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _insightsLoading = true;
        _insightsError = null;
      });
    }

    try {
      final payload = await AuthService.instance.getMoodInsights(
        authToken: token,
      );
      final insights = _MoodInsights.fromJson(payload);
      await prefs.setString(_kAiInsightsCacheKey, jsonEncode(payload));
      await prefs.setInt(
        _kAiInsightsCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      final aiTasks = _decodeAiTasks(payload['tasks'] as List<dynamic>?);
      // Use AI tasks if available, otherwise fall back to mood-lifting defaults
      final tasksToApply = aiTasks.isNotEmpty ? aiTasks : _fallbackTasks();
      await _applyAiTasks(tasksToApply, resetProgress: false);
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _insightsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // On error, ensure tasks are never empty — apply fallback if needed
      if (_todayTasks.isEmpty) {
        await _applyAiTasks(_fallbackTasks(), resetProgress: false);
      }
      setState(() {
        _insightsError = e.toString();
        _insightsLoading = false;
      });
    }
  }

  Future<void> _loadMoodAnalysis() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAiAnalysisCacheKey);
    final ts = prefs.getInt(_kAiAnalysisCacheTsKey);
    if (mounted) {
      setState(() {
        _analysisError = null;
      });
    }
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _analysis = _MoodAnalysis.fromJson(decoded);
            _analysisLoading = false;
          });
        }
      } catch (_) {}
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isFresh =
        ts != null && nowMs - ts < _kAiAnalysisCacheTtl.inMilliseconds;
    if (!isFresh && mounted) {
      setState(() {
        _analysisLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _decodeMoodLogsCache(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _buildMoodHistory(
    String scope,
    List<Map<String, dynamic>> entries,
  ) {
    final now = DateTime.now();
    final keys = <String>[];
    final days = scope == 'day' ? 1 : 7;
    for (int i = days - 1; i >= 0; i -= 1) {
      keys.add(_toDateKey(now.subtract(Duration(days: i))));
    }

    final byKey = <String, Map<String, dynamic>>{};
    for (final entry in entries) {
      final key = entry['dateKey']?.toString();
      if (key != null) byKey[key] = entry;
    }

    final history = <Map<String, dynamic>>[];
    for (final key in keys) {
      final entry = byKey[key];
      if (entry == null) continue;
      history.add({
        'dateKey': key,
        'moodLevel': entry['moodLevel'],
        'activityScore': entry['activityScore'],
        'moodScore': entry['moodScore'],
        'taskScore': entry['taskScore'],
        'score': entry['score'],
        'activities': entry['activities'],
      });
    }
    return history;
  }

  Future<void> _fetchMoodAnalysis(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) {
        setState(() {
          _analysisError = 'Please log in to analyze your mood.';
          _analysisLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _analysisLoading = true;
        _analysisError = null;
      });
    }

    try {
      final cachedLogs = _decodeMoodLogsCache(
        prefs.getString('mood_logs_cache'),
      );
      final moodHistory = _buildMoodHistory(scope, cachedLogs);
      final payload = await AuthService.instance.analyzeMood(
        authToken: token,
        scope: scope,
        moodHistory: moodHistory,
      );
      final analysis = _MoodAnalysis.fromJson(payload);
      await prefs.setString(
        _kAiAnalysisCacheKey,
        jsonEncode(analysis.toJson()),
      );
      await prefs.setInt(
        _kAiAnalysisCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _analysisLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisError = e.toString();
        _analysisLoading = false;
      });
    }
  }

  Uri? _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed';
    return Uri.tryParse(withScheme);
  }

  Future<void> _launchUrl(String url) async {
    final uri = _normalizeUrl(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _loadJournalPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kJournalPreviewCacheKey);
    final ts = prefs.getInt(_kJournalPreviewCacheTsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _journalPreview = _JournalPreview.fromJson(decoded);
            _journalLoading = false;
          });
        }
      } catch (_) {}
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isFresh =
        ts != null && nowMs - ts < _kJournalPreviewCacheTtl.inMilliseconds;
    if (isFresh) return;
    await _fetchJournalPreview();
  }

  Future<void> _fetchJournalPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      if (mounted) setState(() => _journalLoading = false);
      return;
    }

    if (mounted) {
      setState(() {
        _journalLoading = true;
        _journalError = null;
      });
    }

    try {
      final entries = await AuthService.instance.getMyJournalEntries(
        authToken: token,
      );
      if (entries.isEmpty) {
        if (mounted) setState(() => _journalLoading = false);
        return;
      }
      final preview = _JournalPreview.fromJson(entries.first);
      await prefs.setString(
        _kJournalPreviewCacheKey,
        jsonEncode(preview.toJson()),
      );
      await prefs.setInt(
        _kJournalPreviewCacheTsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() {
        _journalPreview = preview;
        _journalLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _journalError = e.toString();
        _journalLoading = false;
      });
    }
  }

  Future<void> _loadMiniCalendarFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('mood_logs_cache');
    if (raw == null) {
      if (mounted) setState(() => _miniCalendarDays = _buildMiniCalendar([]));
      await _fetchMiniCalendarFromBackend();
      return;
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final entries = decoded.whereType<Map<String, dynamic>>().toList(
        growable: false,
      );
      if (mounted) {
        setState(() => _miniCalendarDays = _buildMiniCalendar(entries));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _miniCalendarDays = _buildMiniCalendar([]));
      }
    }
    await _fetchMiniCalendarFromBackend();
  }

  Future<void> _fetchMiniCalendarFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final resp = await http.get(
        Uri.parse('$kBackendBaseUrl/api/moods'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await prefs.setString('mood_logs_cache', resp.body);
        final decoded = jsonDecode(resp.body) as List<dynamic>;
        final entries = decoded.whereType<Map<String, dynamic>>().toList(
          growable: false,
        );
        if (mounted) {
          setState(() => _miniCalendarDays = _buildMiniCalendar(entries));
        }
      }
    } catch (_) {
      // Keep existing cache on failures.
    }
  }

  List<_MiniMoodDay> _buildMiniCalendar(List<Map<String, dynamic>> entries) {
    final map = <String, Map<String, dynamic>>{};
    for (final entry in entries) {
      final key = entry['dateKey']?.toString();
      if (key != null) map[key] = entry;
    }

    final now = DateTime.now();
    final days = <_MiniMoodDay>[];
    for (int i = 6; i >= 0; i--) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      final key = _toDateKey(date);
      final entry = map[key];
      final rawScore = entry?['score'] ?? entry?['moodScore'];
      final score = rawScore is num ? rawScore.round() : null;
      days.add(_MiniMoodDay(label: _weekdayLabel(date.weekday), score: score));
    }
    return days;
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'M';
      case DateTime.tuesday:
        return 'T';
      case DateTime.wednesday:
        return 'W';
      case DateTime.thursday:
        return 'T';
      case DateTime.friday:
        return 'F';
      case DateTime.saturday:
        return 'S';
      default:
        return 'S';
    }
  }

  Future<void> _refreshStreak({bool showFeedback = false}) async {
    final previous = _streakCount;
    final prefs = await SharedPreferences.getInstance();
    final streak = await StreakUtils.refreshFromMoodCache(prefs);
    if (!mounted) return;
    setState(() {
      _streakCount = streak;
    });

    if (!showFeedback || !mounted) return;
    if (previous > 0 && streak == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Streak reset. Log your mood daily to keep it going.'),
        ),
      );
      return;
    }
    if (streak > previous && streak == 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Streak started: Day 1!')));
      return;
    }
    if (streak > previous) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Streak updated: $streak days!')));
    }
  }

  Future<void> _upsertTaskProgressInMoodCache(
    String dateKey,
    int taskPoints,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawCache = prefs.getString('mood_logs_cache');
    List<dynamic> cacheData = [];
    if (rawCache != null) {
      try {
        cacheData = jsonDecode(rawCache) as List<dynamic>;
      } catch (_) {
        cacheData = [];
      }
    }

    final idx = cacheData.indexWhere(
      (d) => d is Map<String, dynamic> && d['dateKey'] == dateKey,
    );

    if (idx >= 0) {
      final entry = Map<String, dynamic>.from(
        cacheData[idx] as Map<String, dynamic>,
      );
      final moodScore = (entry['moodScore'] as num?)?.toInt() ?? 0;
      final activityScore = (entry['activityScore'] as num?)?.toInt() ?? 0;
      final activities = (entry['activities'] as List?) ?? const [];
      final hasMood = (entry['moodLevel'] as int?) != null;

      if (taskPoints > 0) {
        entry['taskScore'] = taskPoints;
      } else {
        entry.remove('taskScore');
      }
      entry['score'] = taskPoints + moodScore;

      final hasProgress =
          hasMood ||
          activityScore > 0 ||
          activities.isNotEmpty ||
          taskPoints > 0;
      if (hasProgress) {
        cacheData[idx] = entry;
      } else {
        cacheData.removeAt(idx);
      }
    } else if (taskPoints > 0) {
      cacheData.add({
        'dateKey': dateKey,
        'activities': <String>[],
        'activityScore': 0,
        'moodScore': 0,
        'taskScore': taskPoints,
        'score': taskPoints,
      });
    }

    await prefs.setString('mood_logs_cache', jsonEncode(cacheData));
  }

  /// Called when user taps a mood icon on the home screen.
  /// Saves moodLevel to DB (backend computes moodLevelScore) and updates cache
  /// so the calendar pre-selects the same mood for today.
  Future<void> _selectMood(int index) async {
    final moodLevelScore = _homeMoodLevelPoints[index];
    final newMoodScore = moodLevelScore + _todayActivityScore;
    setState(() {
      _selectedMood = index;
      _moodScore = _taskPoints + newMoodScore;
    });
    final today = _dateKey();
    final prefs = await SharedPreferences.getInstance();
    // Update (or create) today's entry in the shared cache
    final rawCache = prefs.getString('mood_logs_cache');
    List<dynamic> cacheData = [];
    if (rawCache != null) {
      try {
        cacheData = jsonDecode(rawCache);
      } catch (_) {}
    }
    final idx = cacheData.indexWhere((d) => d['dateKey'] == today);
    if (idx >= 0) {
      cacheData[idx]['moodLevel'] = index + 1;
      cacheData[idx]['moodScore'] = newMoodScore;
      cacheData[idx]['score'] = _taskPoints + newMoodScore;
    } else {
      cacheData.add({
        'dateKey': today,
        'moodLevel': index + 1,
        'activities': <String>[],
        'activityScore': 0,
        'moodScore': moodLevelScore,
        'score': _taskPoints + moodLevelScore,
      });
    }
    await prefs.setString('mood_logs_cache', jsonEncode(cacheData));
    await prefs.remove(_kAiInsightsCacheKey);
    await prefs.remove(_kAiInsightsCacheTsKey);
    await prefs.remove(_kAiAnalysisCacheKey);
    await prefs.remove(_kAiAnalysisCacheTsKey);
    await _refreshStreak(showFeedback: true);
    // Sync to DB — server auto-computes moodLevelScore and merges with existing data
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('$kBackendBaseUrl/api/moods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'dateKey': today, 'moodLevel': index + 1}),
      );
    } catch (_) {}
    await _refreshAfterMoodUpdate();
  }

  Future<void> _completeTask(int index) async {
    if (_completedStates[index]) return;
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final newTaskPoints = _taskPoints + _todayTasks[index].points;
    setState(() {
      _completedStates[index] = true;
      _taskPoints = newTaskPoints;
      _moodScore = _moodScore + _todayTasks[index].points;
    });
    await prefs.setString(
      'tasks_completed',
      _completedStates.map((b) => '$b').join(','),
    );
    await prefs.setInt('mood_score_$today', newTaskPoints);
    await _upsertTaskProgressInMoodCache(today, newTaskPoints);
    await _refreshStreak(showFeedback: true);
    _syncScoreToDb(today, newTaskPoints);
  }

  Future<void> _undoTask(int index) async {
    if (!_completedStates[index]) return;
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final newTaskPoints = (_taskPoints - _todayTasks[index].points).clamp(
      0,
      9999,
    );
    final newMoodScore = (_moodScore - _todayTasks[index].points).clamp(
      0,
      9999,
    );
    setState(() {
      _completedStates[index] = false;
      _taskPoints = newTaskPoints;
      _moodScore = newMoodScore;
    });
    await prefs.setString(
      'tasks_completed',
      _completedStates.map((b) => '$b').join(','),
    );
    await prefs.setInt('mood_score_$today', newTaskPoints);
    await _upsertTaskProgressInMoodCache(today, newTaskPoints);
    await _refreshStreak(showFeedback: true);
    _syncScoreToDb(today, newTaskPoints);
  }

  void _syncScoreToDb(String dateKey, int taskScore) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('$kBackendBaseUrl/api/moods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'dateKey': dateKey, 'taskScore': taskScore}),
      );
    } catch (_) {}
  }

  int get _pendingCount => _completedStates.where((c) => !c).length;

  String get _companionAsset => 'assets/doodle${widget.companionId}.png';

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning!';
    if (hour < 17) return 'Good afternoon!';
    return 'Good evening!';
  }

  String get _formattedDate {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  void _openShellTab(MoodiaryTab tab, {bool fromSidebar = false}) {
    setState(() => _sidebarOpen = false);
    final onShellTabSelected = widget.onShellTabSelected;
    if (onShellTabSelected != null) {
      onShellTabSelected(tab, fromSidebar: false);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          initialTab: tab,
          initialHideTopNav: false,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _openCalendarScreen() async {
    await Navigator.of(context).push(
      FadeSlideRoute(
        page: CalendarScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
        ),
      ),
    );
    await _refreshAfterMoodUpdate();
  }

  Future<void> _openJournalScreen() async {
    await Navigator.of(context).push(
      FadeSlideRoute(
        page: JournalScreen(
          userName: widget.userName,
          companionId: widget.companionId,
          companionName: widget.companionName,
        ),
      ),
    );
    await _loadJournalPreview();
  }

  void _handleCalendarTap() async {
    await _openCalendarScreen();
  }

  void _handleJournalTap() async {
    await _openJournalScreen();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_name');
    await prefs.remove('user_id');
    RealtimeNotifications.instance.disconnect();
    await ThemeController.instance.resetToDefault();
    await LocalNotificationsService.instance.cancelAllScheduled();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        FadeSlideRoute(page: const OnboardingScreen()),
        (_) => false,
      );
    }
  }

  void _showTaskDetail(int index) {
    if (_todayTasks.isEmpty) return;
    final task = _todayTasks[index];
    final isCompleted = _completedStates[index];
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: context.mdSurface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TaskArtwork(task: task, size: 80),
              const SizedBox(height: 16),
              Text(
                task.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.mdPrimaryText,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? (context.isDarkMode
                            ? const Color(0xFF1D3B2F)
                            : const Color(0xFFDCFCE7))
                      : (context.isDarkMode
                            ? const Color(0xFF22263D)
                            : const Color(0xFFF3F0FB)),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  isCompleted ? '✓ Completed' : '+${task.points} pts',
                  style: TextStyle(
                    color: isCompleted ? const Color(0xFF16A34A) : _kPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                task.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.mdSecondaryText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: isCompleted
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _undoTask(index);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.mdSecondaryText,
                                side: BorderSide(
                                  color: context.isDarkMode
                                      ? Colors.white24
                                      : const Color(0xFFDDDDDD),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                              ),
                              child: const Icon(Icons.undo_rounded, size: 20),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4ADE80),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                              ),
                              child: const Icon(Icons.check_rounded, size: 22),
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _completeTask(index);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPurple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        child: const Text('Complete Task! 🎉'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCompanionChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CompanionChat(
        companionName: widget.companionName,
        companionAsset: _companionAsset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final scaffoldColor = context.mdScaffold;
    final cardColor = context.mdSurface;
    final cardShadow = context.mdCardGlow;

    return Scaffold(
      extendBody: true,
      backgroundColor: scaffoldColor,
      body: Stack(
        children: [
          Column(
            children: [
              _Header(
                formattedDate: _formattedDate,
                greeting: _greeting,
                companionAsset: _companionAsset,
                companionName: widget.companionName,
                collapsed: _headerCollapsed,
                onHamburger: () => setState(() => _sidebarOpen = true),
                onProfileTap: () async {
                  await Navigator.of(
                    context,
                  ).push(FadeSlideRoute(page: const UserProfileScreen()));
                  await _loadProfileAvatar();
                },
                profileAvatarUrl: _profileAvatarUrl,
                profileAvatarImage: _profileAvatarImage,
                onCompanionTap: _showCompanionChat,
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI Insights',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AiInsightsCard(
                          insights: _insights,
                          loading: _insightsLoading,
                          error: _insightsError,
                          onRetry: _fetchAiInsights,
                          analysis: _analysis,
                          analysisLoading: _analysisLoading,
                          analysisError: _analysisError,
                          onAnalyzeDay: () => _fetchMoodAnalysis('day'),
                          onAnalyzeWeek: () => _fetchMoodAnalysis('week'),
                          onOpenResources: () =>
                              _openShellTab(MoodiaryTab.resources),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Your Day',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _MoodScoreCard(
                          score: _moodScore,
                          streakCount: _streakCount,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: cardShadow,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'How are you today?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: primaryText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: List.generate(_moods.length, (i) {
                                  final mood = _moods[i];
                                  final selected = _selectedMood == i;
                                  return TapScale(
                                    scale: 0.9,
                                    onTap: () => _selectMood(i),
                                    child: AnimatedScale(
                                      scale: selected ? 1.2 : 1.0,
                                      duration: DataSaverMode.gateDuration(
                                        normal: const Duration(
                                          milliseconds: 200,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Image.asset(
                                            mood.asset,
                                            width: 44,
                                            height: 44,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Icon(
                                                      Icons.sentiment_neutral,
                                                      size: 44,
                                                      color: subtleText,
                                                    ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            mood.label,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: selected
                                                  ? _kPurple
                                                  : subtleText,
                                              fontWeight: selected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _HomeCalendarJournalCard(
                          days: _miniCalendarDays,
                          journal: _journalPreview,
                          journalLoading: _journalLoading,
                          journalError: _journalError,
                          onCalendarTap: _handleCalendarTap,
                          onJournalTap: _handleJournalTap,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Today's Tasks",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                            ),
                            if (_pendingCount > 0)
                              Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$_pendingCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_tasksLoading)
                          _TasksLoadingIndicator()
                        else if (_todayTasks.isEmpty)
                          _AiTasksEmptyState(onRetry: _fetchAiInsights)
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final crossAxisCount = constraints.maxWidth >= 700
                                  ? 2
                                  : 1;
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _todayTasks.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: crossAxisCount == 1
                                          ? 3.4
                                          : 3.0,
                                    ),
                                itemBuilder: (context, i) => _TaskTile(
                                  task: _todayTasks[i],
                                  completed: _completedStates[i],
                                  onTap: () => _showTaskDetail(i),
                                ),
                              );
                            },
                          ),
                        SizedBox(
                          height: MediaQuery.of(context).padding.bottom + 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _sidebarOpen = false),
                child: Container(color: context.mdOverlayBarrier),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: _sidebarOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 260,
            child: AppSidebar(
              userName: widget.userName,
              activeSection: SidebarSection.home,
              onClose: () => setState(() => _sidebarOpen = false),
              onNavigateHome: () => setState(() => _sidebarOpen = false),
              onNavigateUserProfile: () => _openShellTab(MoodiaryTab.profile),
              onNavigateCalendar: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: CalendarScreen(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                    ),
                  ),
                );
              },
              onNavigateJournal: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: JournalScreen(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                    ),
                  ),
                );
              },
              onNavigateFriends: () => _openShellTab(MoodiaryTab.buddies),
              onNavigateForums: () => _openShellTab(MoodiaryTab.forums),
              onNavigateResources: () => _openShellTab(MoodiaryTab.resources),
              onNavigateSettings: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: SettingsScreen(userName: widget.userName),
                  ),
                );
              },
              onChangeCompanion: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: CompanionScreen(userName: widget.userName),
                  ),
                );
              },
              onLogout: () {
                setState(() => _sidebarOpen = false);
                _logout();
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav
          ? _sidebarOpen
                ? null
                : _BottomNav(
                    userName: widget.userName,
                    companionId: widget.companionId,
                    companionName: widget.companionName,
                  )
          : null,
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String formattedDate;
  final String greeting;
  final String companionAsset;
  final String companionName;
  final bool collapsed;
  final String? profileAvatarUrl;
  final ImageProvider<Object>? profileAvatarImage;
  final VoidCallback onHamburger;
  final VoidCallback onProfileTap;
  final VoidCallback onCompanionTap;

  const _Header({
    required this.formattedDate,
    required this.greeting,
    required this.companionAsset,
    required this.companionName,
    required this.collapsed,
    required this.profileAvatarUrl,
    required this.profileAvatarImage,
    required this.onHamburger,
    required this.onProfileTap,
    required this.onCompanionTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: SizedBox(
          width: double.infinity,
          child: GlassContainer(
            blurSigma: context.mdGlassBlurSmall,
            borderRadius: BorderRadius.circular(22),
            backgroundColor: context.mdGlassSurfaceStrong,
            borderColor: context.mdGlassBorder,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: onHamburger,
                      icon: Icon(Icons.menu, color: primaryText, size: 26),
                      tooltip: 'Open menu',
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          formattedDate,
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onProfileTap,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: context.mdGlassSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.mdGlassBorder),
                        ),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.transparent,
                          backgroundImage: profileAvatarImage,
                          child: profileAvatarImage == null
                              ? Icon(Icons.person, color: primaryText, size: 18)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: context.mdHeaderCollapseDuration,
                  curve: Curves.easeOutCubic,
                  child: collapsed
                      ? const SizedBox.shrink()
                      : AnimatedOpacity(
                          duration: context.mdHeaderFadeDuration,
                          opacity: collapsed ? 0 : 1,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Home',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: primaryText,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '$greeting Ready to take care of yourself today?',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TapScale(
                    onTap: onCompanionTap,
                    child: GlassContainer(
                      blurSigma: context.mdGlassBlurSmall,
                      borderRadius: BorderRadius.circular(14),
                      backgroundColor: context.mdGlassSurface,
                      borderColor: context.mdGlassBorder,
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: collapsed ? 6 : 8,
                      ),
                      child: Row(
                        children: [
                          Image.asset(
                            companionAsset,
                            width: collapsed ? 28 : 34,
                            height: collapsed ? 28 : 34,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.sentiment_satisfied_alt,
                              size: collapsed ? 22 : 26,
                              color: secondaryText,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              collapsed
                                  ? 'Talk to companion'
                                  : 'Talk with $companionName',
                              style: TextStyle(
                                color: primaryText,
                                fontSize: collapsed ? 12 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: secondaryText,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
}

// ─── Task Card ────────────────────────────────────────────────────────────────
class _TaskArtwork extends StatelessWidget {
  final _MoodTask task;
  final double size;

  const _TaskArtwork({required this.task, required this.size});

  @override
  Widget build(BuildContext context) {
    final accent = task.iconColor;
    final background = task.iconBackground;
    final gradientTop =
        Color.lerp(background, Colors.white, 0.55) ?? background;
    final gradientBottom =
        Color.lerp(background, Colors.black, 0.05) ?? background;

    final fallbackIcon = task.icon ?? Icons.auto_awesome_rounded;
    Widget content;
    if (task.asset != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          task.asset!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              _TaskGlyph(icon: fallbackIcon, color: accent, size: size * 0.52),
        ),
      );
    } else {
      content = _TaskGlyph(
        icon: fallbackIcon,
        color: accent,
        size: size * 0.52,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientTop, gradientBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.35),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: EdgeInsets.all(size * 0.18), child: content),
    );
  }
}

class _TaskGlyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _TaskGlyph({
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: Icon(icon, color: color, size: size),
    );
  }
}

Color _miniDotColor(int score) {
  if (score >= 70) return const Color(0xFF10B981);
  if (score >= 40) return const Color(0xFF84CC16);
  if (score >= 20) return const Color(0xFFFACC15);
  if (score >= 0) return const Color(0xFFF97316);
  return const Color(0xFFEF4444);
}

class _AiInsightsCard extends StatelessWidget {
  final _MoodInsights? insights;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final _MoodAnalysis? analysis;
  final bool analysisLoading;
  final String? analysisError;
  final VoidCallback onAnalyzeDay;
  final VoidCallback onAnalyzeWeek;
  final VoidCallback onOpenResources;

  const _AiInsightsCard({
    required this.insights,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.analysis,
    required this.analysisLoading,
    required this.analysisError,
    required this.onAnalyzeDay,
    required this.onAnalyzeWeek,
    required this.onOpenResources,
  });

  String _trendText(_MoodInsights? insights) {
    if (insights == null) return 'Log a few moods to unlock insights.';
    final count = insights.last7.where((v) => v != null).length;
    if (count < 3) return 'Log a few more moods to unlock insights.';
    final direction = insights.trendDirection;
    final percent = insights.trendPercent.abs();
    if (direction == 'steady' || percent == 0) {
      return 'Your mood is steady this week.';
    }
    final label = direction == 'improving' ? 'improving' : 'declining';
    return 'Your mood is $label $percent% this week.';
  }

  String _analysisReflection(_MoodAnalysis analysis) {
    final mood = analysis.detectedMood.trim();
    final scope = analysis.scope == 'week' ? 'this week' : 'today';
    if (mood.isEmpty) {
      return 'Clinical summary for $scope is available. Review resources for evidence-based support.';
    }
    return 'Clinical summary for $scope: mood state is $mood. Review resources for evidence-based support.';
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final chipBg = context.isDarkMode
        ? const Color(0xFF23263A)
        : const Color(0xFFF3F0FB);
    final gradientColors = context.isDarkMode
        ? [const Color(0xFF1A1E33), const Color(0xFF101221)]
        : [const Color(0xFFF8F4FF), const Color(0xFFEDE9FE)];

    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Weekly pulse',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: primaryText,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded, color: subtleText, size: 20),
                tooltip: 'Refresh insights',
              ),
            ],
          ),
          Text(
            _trendText(insights),
            style: TextStyle(fontSize: 13, color: subtleText),
          ),
          const SizedBox(height: 12),
          if (loading && insights == null)
            const Center(child: CircularProgressIndicator())
          else if (insights == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We could not load insights yet.',
                  style: TextStyle(fontSize: 13, color: subtleText),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: insights!.last7.map((value) {
                    final label = value == null ? '--' : value.toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: primaryText,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                if (insights!.aiMessage.trim().isNotEmpty)
                  Text(
                    '"${insights!.aiMessage.trim()}"',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: primaryText,
                    ),
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: analysisLoading ? null : onAnalyzeDay,
                      child: const Text('Analyze my day (Today)'),
                    ),
                    OutlinedButton(
                      onPressed: analysisLoading ? null : onAnalyzeWeek,
                      child: const Text('Analyze my week'),
                    ),
                  ],
                ),
                if (analysisLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kPurple.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Analyzing your mood...',
                          style: TextStyle(fontSize: 12, color: subtleText),
                        ),
                      ],
                    ),
                  ),
                if (!analysisLoading && analysisError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      analysisError!,
                      style: TextStyle(fontSize: 11, color: subtleText),
                    ),
                  ),
                if (!analysisLoading && analysis != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _analysisReflection(analysis!),
                          style: TextStyle(fontSize: 12, color: primaryText),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: onOpenResources,
                          icon: const Icon(
                            Icons.folder_open_outlined,
                            size: 16,
                          ),
                          label: const Text('Open resources'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                // Boosters/tasks are shown in the "Today's Tasks" section instead
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Refresh failed. Showing last saved insights.',
                      style: TextStyle(fontSize: 11, color: subtleText),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HomeCalendarJournalCard extends StatelessWidget {
  final List<_MiniMoodDay> days;
  final _JournalPreview? journal;
  final bool journalLoading;
  final String? journalError;
  final VoidCallback onCalendarTap;
  final VoidCallback onJournalTap;

  const _HomeCalendarJournalCard({
    required this.days,
    required this.journal,
    required this.journalLoading,
    required this.journalError,
    required this.onCalendarTap,
    required this.onJournalTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final dividerColor = context.isDarkMode
        ? Colors.white12
        : const Color(0xFFE6E6E6);
    final emptyDotColor = context.isDarkMode
        ? const Color(0xFF2A2F45)
        : const Color(0xFFE5E7EB);

    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: TapScale(
              onTap: onCalendarTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calendar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: days.isEmpty
                        ? List.generate(
                            7,
                            (i) => _MiniDot(label: '', color: emptyDotColor),
                          )
                        : days
                              .map(
                                (day) => _MiniDot(
                                  label: day.label,
                                  color: day.score == null
                                      ? emptyDotColor
                                      : _miniDotColor(day.score!),
                                ),
                              )
                              .toList(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to open your calendar',
                    style: TextStyle(fontSize: 11, color: subtleText),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 78, color: dividerColor),
          const SizedBox(width: 12),
          Expanded(
            child: TapScale(
              onTap: onJournalTap,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Journal',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (journalLoading)
                      Text(
                        'Loading entry...',
                        style: TextStyle(fontSize: 11, color: subtleText),
                      )
                    else if (journal == null)
                      Text(
                        'Write your first entry',
                        style: TextStyle(fontSize: 11, color: subtleText),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            journal!.title.isEmpty
                                ? 'Untitled'
                                : journal!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            journal!.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: subtleText),
                          ),
                        ],
                      ),
                    if (journalError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Tap to retry.',
                          style: TextStyle(fontSize: 10, color: subtleText),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDot extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: context.mdSecondaryText),
        ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final _MoodTask task;
  final bool completed;
  final VoidCallback onTap;

  const _TaskTile({
    required this.task,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final badgeBg = context.isDarkMode
        ? const Color(0xFF2C2F45)
        : const Color(0xFFF3F0FB);

    return TapScale(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: completed ? 0.65 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: GlassContainer(
          blurSigma: context.mdGlassBlurMedium,
          backgroundColor: context.mdGlassSurface,
          borderColor: context.mdGlassBorder,
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _TaskArtwork(task: task, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: primaryText,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: subtleText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (completed)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF4ADE80),
                  size: 24,
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    '+${task.points} pts',
                    style: const TextStyle(
                      color: _kPurple,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tasks Loading Indicator ─────────────────────────────────────────────────
class _TasksLoadingIndicator extends StatelessWidget {
  const _TasksLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    final shimmerBase = context.isDarkMode
        ? const Color(0xFF1F2337)
        : const Color(0xFFF0EDF8);
    final shimmerHighlight = context.isDarkMode
        ? const Color(0xFF2A2F4A)
        : const Color(0xFFE8E3F5);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _kPurple.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Generating personalized tasks...',
              style: TextStyle(
                fontSize: 13,
                color: subtleText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassContainer(
              blurSigma: context.mdGlassBlurMedium,
              backgroundColor: context.mdGlassSurface,
              borderColor: context.mdGlassBorder,
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: shimmerBase,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: shimmerHighlight,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 120 + i * 20.0,
                          height: 12,
                          decoration: BoxDecoration(
                            color: shimmerBase,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          height: 10,
                          decoration: BoxDecoration(
                            color: shimmerBase,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiTasksEmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _AiTasksEmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final subtleText = context.mdSecondaryText;
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'No AI tasks yet.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.mdPrimaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Refresh AI Insights to generate new tasks based on your latest data.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: subtleText),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ─── Mood Score Card ──────────────────────────────────────────────────────────
class _MoodScoreCard extends StatelessWidget {
  final int score;
  final int streakCount;
  const _MoodScoreCard({required this.score, required this.streakCount});

  String get _statusLabel {
    if (score >= 100) return 'Thriving 🌟';
    if (score >= 70) return 'Great 😊';
    if (score >= 40) return 'Good 🙂';
    if (score >= 20) return 'Moderate 😐';
    if (score > 0) return 'Low 😔';
    if (score < 0) return 'Struggling 💙';
    return 'No score yet 💤';
  }

  String get _message {
    if (score >= 100) return 'You\'re having an amazing day!';
    if (score >= 70) return 'Keep up the great energy!';
    if (score >= 40) return 'Solid day, well done!';
    if (score >= 20) return 'You\'re making progress!';
    if (score > 0) return 'Small steps still count!';
    if (score < 0) return 'Take it easy — it\'s okay.';
    return 'Log a mood or complete a task!';
  }

  Color get _statusColor {
    if (score >= 100) return const Color(0xFF10B981);
    if (score >= 70) return const Color(0xFF84CC16);
    if (score >= 40) return const Color(0xFF60A5FA);
    if (score >= 20) return const Color(0xFFFBBF24);
    if (score > 0) return const Color(0xFFF97316);
    if (score < 0) return const Color(0xFFEF4444);
    return const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final gradientColors = context.isDarkMode
        ? [const Color(0xFF1E2234), const Color(0xFF121424)]
        : [const Color(0xFFF3F0FB), const Color(0xFFEDE9FE)];

    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(20),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🌟 Mood Score',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: primaryText,
                ),
              ),
              Row(
                children: [
                  Text(
                    '$score pts',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _kPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _statusColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_message, style: TextStyle(fontSize: 12, color: subtleText)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFB923C).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFFB923C).withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              '🔥 Streak: $streakCount ${streakCount == 1 ? 'day' : 'days'}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFFEA580C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Nav ───────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final String userName;
  final int companionId;
  final String companionName;
  const _BottomNav({
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
        Icons.account_circle_outlined,
        'Profile',
        onTap: () {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: MoodiaryShell(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
                initialTab: MoodiaryTab.profile,
              ),
            ),
            (_) => false,
          );
        },
      ),
      _NavItem(
        Icons.people_alt_rounded,
        'Buddies',
        onTap: () {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: MoodiaryShell(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
                initialTab: MoodiaryTab.buddies,
              ),
            ),
            (_) => false,
          );
        },
      ),
      _NavItem(Icons.home_rounded, 'Home', active: true, onTap: () {}),
      _NavItem(
        Icons.chat_bubble_outline,
        'Forums',
        onTap: () {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: MoodiaryShell(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
                initialTab: MoodiaryTab.forums,
              ),
            ),
            (_) => false,
          );
        },
      ),
      _NavItem(
        Icons.folder_outlined,
        'Resources',
        onTap: () {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: MoodiaryShell(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
                initialTab: MoodiaryTab.resources,
              ),
            ),
            (_) => false,
          );
        },
      ),
    ];
    final navBg = context.mdSurface;
    final borderColor = context.isDarkMode
        ? Colors.white10
        : const Color(0xFFF0F0F0);
    final inactiveColor = context.mdSecondaryText;

    final media = MediaQuery.of(context);
    final horizontalInset = media.size.width >= 700 ? 20.0 : 16.0;
    final bottomInset = media.padding.bottom > 0 ? 4.0 : 8.0;

    return SafeArea(
      minimum: EdgeInsets.fromLTRB(
        horizontalInset,
        0,
        horizontalInset,
        bottomInset,
      ),
      child: GlassContainer(
        blurSigma: context.mdGlassBlurSmall,
        borderRadius: BorderRadius.circular(context.mdRadiusLg),
        backgroundColor: navBg.withValues(
          alpha: context.isDarkMode ? 0.62 : 0.78,
        ),
        borderColor: borderColor,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items
              .map(
                (item) => TapScale(
                  onTap: item.onTap,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: item.active ? _kPurple : inactiveColor,
                        size: 22,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 8,
                          color: item.active ? _kPurple : inactiveColor,
                          fontWeight: item.active
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(
    this.icon,
    this.label, {
    this.active = false,
    required this.onTap,
  });
}

// ─── Companion Chat ──────────────────────────────────────────────────────────
class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}

class _CompanionChat extends StatefulWidget {
  final String companionName;
  final String companionAsset;
  const _CompanionChat({
    required this.companionName,
    required this.companionAsset,
  });

  @override
  State<_CompanionChat> createState() => _CompanionChatState();
}

class _CompanionChatState extends State<_CompanionChat> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  String? _token;

  static const _kBaseUrl = kBackendBaseUrl;

  static const _prompts = [
    'Tell me a motivational quote.',
    'What should I do today?',
    'I am feeling anxious.',
    'Help me calm down.',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _token = prefs.getString('token');
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    if (_token == null) {
      _addCompanion(
        'Hi! I\'m ${widget.companionName}. How are you feeling today?',
      );
      return;
    }
    try {
      final response = await http.get(
        Uri.parse(
          '$_kBaseUrl/api/chat/${Uri.encodeComponent(widget.companionName)}',
        ),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (!mounted) return;
      final data = jsonDecode(response.body);
      final List<dynamic> msgs = data['messages'] ?? [];
      if (msgs.isEmpty) {
        _addCompanion(
          'Hi! I\'m ${widget.companionName}. How are you feeling today?',
        );
      } else {
        setState(() {
          for (final m in msgs) {
            _messages.add(
              _ChatMessage(
                text: m['text'] as String,
                isUser: m['role'] == 'user',
              ),
            );
          }
        });
        _scrollDown();
      }
    } catch (_) {
      _addCompanion(
        'Hi! I\'m ${widget.companionName}. How are you feeling today?',
      );
    }
  }

  void _addCompanion(String text) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(text: text, isUser: false)));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty || _loading) return;
    _input.clear();
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: msg, isUser: true));
      _loading = true;
    });
    _scrollDown();

    try {
      final response = await http.post(
        Uri.parse('$_kBaseUrl/api/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'companionName': widget.companionName,
          'message': msg,
        }),
      );
      final data = jsonDecode(response.body);
      final reply = data['reply'] ?? data['error'] ?? 'Something went wrong.';
      _addCompanion(reply);
    } catch (_) {
      _addCompanion('Oops, I lost connection. Try again?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showPrompts = _messages.length <= 1;
    final secondarySurface = context.mdSecondarySurface;
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;
    final dividerColor = context.isDarkMode
        ? Colors.white12
        : const Color(0xFFE6E6E6);
    final promptBg = context.isDarkMode
        ? const Color(0xFF2C3250)
        : const Color(0xFFF3F0FB);
    final promptText = context.isDarkMode ? Colors.white : _kPurple;
    final inputFill = context.mdInputFill;
    final inputBorder = context.mdInputBorder;
    final handleColor = context.isDarkMode
        ? Colors.white24
        : const Color(0xFFDDDDDD);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final bottomInset = (viewInsets > 0 ? viewInsets : safeBottom) + 8;

    final width = MediaQuery.of(context).size.width;
    final horizontalInset = width >= 700 ? 20.0 : 12.0;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurMedium,
        margin: EdgeInsets.fromLTRB(horizontalInset, 0, horizontalInset, 8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        backgroundColor: context.mdGlassSurfaceStrong,
        borderColor: context.mdGlassBorder,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // ── Handle bar
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ── Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: secondarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Image.asset(
                        widget.companionAsset,
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.sentiment_satisfied_alt,
                          color: subtleText,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.companionName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: subtleText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: dividerColor),

            // ── Messages
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                itemCount: _messages.length + (_loading ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) {
                    return _TypingBubble(
                      companionAsset: widget.companionAsset,
                    );
                  }
                  final m = _messages[i];
                  return _ChatBubble(message: m);
                },
              ),
            ),

            // ── Quick prompts (only before first user message)
            if (showPrompts)
              Container(
                height: 36,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _prompts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => TapScale(
                    onTap: () => _send(_prompts[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: promptBg,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        _prompts[i],
                        style: TextStyle(color: promptText, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Input row
            Divider(height: 1, color: dividerColor),
            AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _send,
                      style: TextStyle(color: primaryText),
                      decoration: InputDecoration(
                        hintText: 'Say something…',
                        hintStyle: TextStyle(color: subtleText),
                        filled: true,
                        fillColor: inputFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide: BorderSide(color: inputBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide: BorderSide(color: inputBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide: const BorderSide(
                            color: _kPurple,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TapScale(
                    onTap: () => _send(_input.text),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: GlassContainer(
                        blurSigma: context.mdGlassBlurSmall,
                        borderRadius: BorderRadius.circular(23),
                        backgroundColor: _kPurple.withValues(alpha: 0.58),
                        borderColor: context.mdGlassBorder,
                        padding: EdgeInsets.zero,
                        child: const Center(
                          child: Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final companionBg = context.mdSecondarySurface;
    final companionText = context.mdPrimaryText;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? _kPurple : companionBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : companionText,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  final String companionAsset;
  const _TypingBubble({required this.companionAsset});
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubbleBg = context.mdSecondarySurface;
    final dotColor = context.mdSecondaryText;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                final offset = ((_ctrl.value - i * 0.2) % 1.0);
                final dy = offset < 0.5
                    ? -4.0 * (offset / 0.5)
                    : -4.0 * (1 - (offset - 0.5) / 0.5);
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
