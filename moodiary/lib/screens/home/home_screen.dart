import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
const _kLightPurple = Color(0xFFD8B4F8);

// ─── Task pool — 3 are picked randomly every day ─────────────────────────────
const _taskPool = [
  _MoodTask(
    id: 'water',
    title: 'Drink Enough Water',
    description:
        'Staying hydrated is crucial for brain function. Dehydration impairs concentration, memory, and mood. Drink at least 8 glasses today.',
    points: 10,
    asset: 'assets/water.png',
  ),
  _MoodTask(
    id: 'reading',
    title: 'Keep Reading',
    description:
        'Reading for 20 minutes lowers your heart rate and reduces cortisol. It builds vocabulary, empathy, and a steady sense of calm.',
    points: 15,
    asset: 'assets/reading.png',
  ),
  _MoodTask(
    id: 'meditate',
    title: 'Try Meditation',
    description:
        'Just 5 minutes of focused breathing activates your parasympathetic nervous system, reducing anxiety and improving emotional regulation.',
    points: 15,
    asset: 'assets/meditation.png',
  ),
  _MoodTask(
    id: 'walk',
    title: 'Take a 10-Minute Walk',
    description:
        'A brisk walk boosts serotonin and endorphins. Even a short stroll outside can lift your mood for hours afterwards.',
    points: 10,
    icon: Icons.directions_walk_rounded,
    iconColor: Color(0xFF2563EB),
    iconBackground: Color(0xFFE0F2FE),
  ),
  _MoodTask(
    id: 'gratitude',
    title: 'Write 3 Gratitudes',
    description:
        'Journaling what you\'re grateful for rewires your brain toward positivity. Try to be specific — small moments count the most.',
    points: 15,
    icon: Icons.favorite_border_rounded,
    iconColor: Color(0xFFEA580C),
    iconBackground: Color(0xFFFFEDD5),
  ),
  _MoodTask(
    id: 'breathe',
    title: 'Practice Deep Breathing',
    description:
        'Try the 4-7-8 technique: inhale for 4 seconds, hold for 7, exhale for 8. Repeat 3 times to calm your nervous system almost instantly.',
    points: 10,
    icon: Icons.air_rounded,
    iconColor: Color(0xFF0EA5E9),
    iconBackground: Color(0xFFE0F2FE),
  ),
  _MoodTask(
    id: 'stretch',
    title: 'Stretch for 5 Minutes',
    description:
        'Gentle stretching relieves built-up muscle tension and improves blood flow to the brain, making it easier to focus and feel at ease.',
    points: 5,
    icon: Icons.accessibility_new_rounded,
    iconColor: Color(0xFF16A34A),
    iconBackground: Color(0xFFDCFCE7),
  ),
  _MoodTask(
    id: 'sleep',
    title: 'Protect Your Sleep',
    description:
        'Even one extra hour of sleep dramatically improves emotion regulation, memory consolidation, and next-day energy. Guard your bedtime.',
    points: 20,
    icon: Icons.bedtime_rounded,
    iconColor: Color(0xFF7C3AED),
    iconBackground: Color(0xFFEDE9FE),
  ),
  _MoodTask(
    id: 'screen',
    title: 'Take a Screen Break',
    description:
        'Step away from all screens for 15 minutes. Look at something at least 6 metres away to rest your eyes and quiet your mind.',
    points: 10,
    icon: Icons.phonelink_off_rounded,
    iconColor: Color(0xFF6366F1),
    iconBackground: Color(0xFFE0E7FF),
  ),
  _MoodTask(
    id: 'music',
    title: 'Listen to Calming Music',
    description:
        'Music around 60 BPM can induce alpha brainwaves associated with relaxed alertness. Put on a gentle playlist and just breathe.',
    points: 5,
    icon: Icons.music_note_rounded,
    iconColor: Color(0xFFDB2777),
    iconBackground: Color(0xFFFCE7F3),
  ),
  _MoodTask(
    id: 'connect',
    title: 'Reach Out to Someone',
    description:
        'Send a kind message to a friend or family member. Social connection is one of the strongest predictors of long-term mental wellbeing.',
    points: 15,
    icon: Icons.chat_bubble_rounded,
    iconColor: Color(0xFF3B82F6),
    iconBackground: Color(0xFFE0F2FE),
  ),
  _MoodTask(
    id: 'meal',
    title: 'Prepare a Healthy Meal',
    description:
        'What you eat directly shapes your mood via the gut-brain axis. Prepare something colourful and nutritious — even a simple salad counts.',
    points: 20,
    icon: Icons.restaurant_menu,
    iconColor: Color(0xFFDC2626),
    iconBackground: Color(0xFFFFE4E6),
  ),
];

const _moods = [
  _Mood('Terrible', 'assets/terrible.png'),
  _Mood('Bad', 'assets/bad.png'),
  _Mood('Okay', 'assets/okay.png'),
  _Mood('Good', 'assets/good.png'),
  _Mood('Excellent', 'assets/excellent.png'),
];

// Must match calendar_screen.dart _moodLevelPoints
const _homeMoodLevelPoints = [5, 10, 20, 35, 50];

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
  }) : assert(asset != null || icon != null, 'Provide an asset or icon');
}

class _Mood {
  final String label;
  final String asset;
  const _Mood(this.label, this.asset);
}

class HomeScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final String? initialProfileAvatarUrl;
  final bool showBottomNav;

  const HomeScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.initialProfileAvatarUrl,
    this.showBottomNav = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int? _selectedMood;
  bool _sidebarOpen = false;
  String? _profileAvatarUrl;
  ImageProvider<Object>? _profileAvatarImage;

  List<_MoodTask> _todayTasks = [];
  List<bool> _completedStates = [false, false, false];
  int _taskPoints = 0; // points from task completions only
  int _todayActivityScore = 0; // activity score from calendar log (today)
  int _moodScore = 0; // combined: taskPoints + moodLevelScore + activityScore
  int _streakCount = 0;

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

  String _dateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final savedDate = prefs.getString('tasks_date');

    List<int> indices;
    List<bool> completed;

    if (savedDate != today) {
      // Pick 3 tasks using a deterministic seed from the date so every user
      // gets a different-but-consistent set each day, with variety across days.
      final parts = today.split('-');
      final seed =
          int.parse(parts[0]) * 10000 +
          int.parse(parts[1]) * 100 +
          int.parse(parts[2]);
      final rng = Random(seed);
      final all = List.generate(_taskPool.length, (i) => i);
      // Fisher-Yates with seeded rng
      for (int i = all.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = all[i];
        all[i] = all[j];
        all[j] = tmp;
      }
      indices = all.take(3).toList();
      completed = [false, false, false];
      await prefs.setString('tasks_date', today);
      await prefs.setString('tasks_indices', indices.join(','));
      await prefs.setString('tasks_completed', 'false,false,false');
      await prefs.setInt('mood_score_$today', 0);
    } else {
      final idxStr = prefs.getString('tasks_indices') ?? '0,1,2';
      indices = idxStr.split(',').map(int.parse).toList();
      final cStr = prefs.getString('tasks_completed') ?? 'false,false,false';
      completed = cStr.split(',').map((s) => s == 'true').toList();
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
        _todayTasks = indices.map((i) => _taskPool[i]).toList();
        _completedStates = completed;
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Today's Task",
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
                      // ── Mood Score Card ─────────────────────────────────
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
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(_moods.length, (i) {
                                final mood = _moods[i];
                                final selected = _selectedMood == i;
                                return GestureDetector(
                                  onTap: () => _selectMood(i),
                                  child: AnimatedScale(
                                    scale: selected ? 1.2 : 1.0,
                                    duration: const Duration(milliseconds: 200),
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
                      const SizedBox(height: 12),
                      if (_todayTasks.isEmpty)
                        const Center(child: CircularProgressIndicator())
                      else
                        ...List.generate(
                          _todayTasks.length,
                          (i) => _TaskCard(
                            task: _todayTasks[i],
                            completed: _completedStates[i],
                            onTap: () => _showTaskDetail(i),
                          ),
                        ),
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 16,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            GestureDetector(
              onTap: () => setState(() => _sidebarOpen = false),
              child: Container(color: context.mdOverlayBarrier),
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
              onNavigateUserProfile: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(
                    page: MoodiaryShell(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                      initialTab: MoodiaryTab.profile,
                    ),
                  ),
                  (_) => false,
                );
              },
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
              onNavigateFriends: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(
                    page: MoodiaryShell(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                      initialTab: MoodiaryTab.buddies,
                    ),
                  ),
                  (_) => false,
                );
              },
              onNavigateForums: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(
                    page: MoodiaryShell(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                      initialTab: MoodiaryTab.forums,
                    ),
                  ),
                  (_) => false,
                );
              },
              onNavigateResources: () {
                setState(() => _sidebarOpen = false);
                Navigator.of(context).pushAndRemoveUntil(
                  FadeSlideRoute(
                    page: MoodiaryShell(
                      userName: widget.userName,
                      companionId: widget.companionId,
                      companionName: widget.companionName,
                      initialTab: MoodiaryTab.resources,
                    ),
                  ),
                  (_) => false,
                );
              },
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
              onLogout: _logout,
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav
          ? _BottomNav(
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
    required this.profileAvatarUrl,
    required this.profileAvatarImage,
    required this.onHamburger,
    required this.onProfileTap,
    required this.onCompanionTap,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = context.mdSurface;
    final bubbleText = context.mdPrimaryText;
    final bubbleShadow = context.mdCardGlow;
    final avatarHalo = context.isDarkMode
        ? const Color(0xFFf4be45)
        : const Color(0xFFFEF08A);
    final avatarBorder = context.isDarkMode ? Colors.white24 : Colors.white;

    return ClipPath(
      clipper: _WavyClipper(),
      child: Container(
        height: 210,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_kLightPurple, _kPurple],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: onHamburger,
                    ),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    GestureDetector(
                      onTap: onProfileTap,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Colors.transparent,
                          backgroundImage: profileAvatarImage,
                          child: profileAvatarImage == null
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 22,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(color: bubbleShadow, blurRadius: 8),
                          ],
                        ),
                        child: Text(
                          '$greeting\nReady to take care of yourself today? Tap on me to talk!',
                          style: TextStyle(
                            color: bubbleText,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TapScale(
                      onTap: onCompanionTap,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: avatarHalo,
                          shape: BoxShape.circle,
                          border: Border.all(color: avatarBorder, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Image.asset(
                            companionAsset,
                            width: 70,
                            height: 70,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.sentiment_satisfied_alt,
                                  size: 50,
                                  color: Color(0xFFCCCCCC),
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width * 0.5,
      size.height + 20,
      size.width,
      size.height - 30,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WavyClipper old) => false;
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

    Widget content;
    if (task.asset != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.asset(
          task.asset!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _TaskGlyph(
            icon: task.icon ?? Icons.task_alt,
            color: accent,
            size: size * 0.52,
          ),
        ),
      );
    } else {
      content = _TaskGlyph(
        icon: task.icon ?? Icons.task_alt,
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

class _TaskCard extends StatelessWidget {
  final _MoodTask task;
  final bool completed;
  final VoidCallback onTap;
  const _TaskCard({
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
        duration: const Duration(milliseconds: 300),
        child: GlassContainer(
          blurSigma: context.mdGlassBlurMedium,
          backgroundColor: context.mdGlassSurface,
          borderColor: context.mdGlassBorder,
          borderRadius: BorderRadius.circular(20),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _TaskArtwork(task: task, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: primaryText,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subtleText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (completed)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF4ADE80),
                  size: 28,
                )
              else
                Row(
                  children: [
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
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: _kPurple,
                      size: 16,
                    ),
                  ],
                ),
            ],
          ),
        ),
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
    _token = prefs.getString('token');
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
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
    setState(() => _messages.add(_ChatMessage(text: text, isUser: false)));
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    return _TypingBubble(companionAsset: widget.companionAsset);
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
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 8,
              ),
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
                        backgroundColor: _kPurple.withValues(alpha: 0.70),
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
