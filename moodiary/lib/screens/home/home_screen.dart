import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../onboarding/onboarding_screen.dart';
import '../companion/companion_screen.dart';
import '../calendar/calendar_screen.dart';
import '../../utils/transitions.dart';

const _kPurple = Color(0xFFA076F9);
const _kLightPurple = Color(0xFFD8B4F8);
const _kDark = Color(0xFF3D3B40);
const _kBg = Color(0xFFF7F5F2);
const _kCardBg = Colors.white;
const _kSubtle = Color(0xFF8A8A8D);

// ─── Task pool — 3 are picked randomly every day ─────────────────────────────
const _taskPool = [
  _MoodTask(
    'water',
    'Drink Enough Water',
    'Staying hydrated is crucial for brain function. Dehydration impairs concentration, memory, and mood. Drink at least 8 glasses today.',
    'assets/water.png',
    10,
  ),
  _MoodTask(
    'reading',
    'Keep Reading',
    'Reading for 20 minutes lowers your heart rate and reduces cortisol. It builds vocabulary, empathy, and a steady sense of calm.',
    'assets/reading.png',
    15,
  ),
  _MoodTask(
    'meditate',
    'Try Meditation',
    'Just 5 minutes of focused breathing activates your parasympathetic nervous system, reducing anxiety and improving emotional regulation.',
    'assets/meditation.png',
    15,
  ),
  _MoodTask(
    'walk',
    'Take a 10-Minute Walk',
    'A brisk walk boosts serotonin and endorphins. Even a short stroll outside can lift your mood for hours afterwards.',
    'assets/water.png',
    10,
  ),
  _MoodTask(
    'gratitude',
    'Write 3 Gratitudes',
    'Journaling what you\'re grateful for rewires your brain toward positivity. Try to be specific — small moments count the most.',
    'assets/reading.png',
    15,
  ),
  _MoodTask(
    'breathe',
    'Practice Deep Breathing',
    'Try the 4-7-8 technique: inhale for 4 seconds, hold for 7, exhale for 8. Repeat 3 times to calm your nervous system almost instantly.',
    'assets/meditation.png',
    10,
  ),
  _MoodTask(
    'stretch',
    'Stretch for 5 Minutes',
    'Gentle stretching relieves built-up muscle tension and improves blood flow to the brain, making it easier to focus and feel at ease.',
    'assets/water.png',
    5,
  ),
  _MoodTask(
    'sleep',
    'Protect Your Sleep',
    'Even one extra hour of sleep dramatically improves emotion regulation, memory consolidation, and next-day energy. Guard your bedtime.',
    'assets/reading.png',
    20,
  ),
  _MoodTask(
    'screen',
    'Take a Screen Break',
    'Step away from all screens for 15 minutes. Look at something at least 6 metres away to rest your eyes and quiet your mind.',
    'assets/meditation.png',
    10,
  ),
  _MoodTask(
    'music',
    'Listen to Calming Music',
    'Music around 60 BPM can induce alpha brainwaves associated with relaxed alertness. Put on a gentle playlist and just breathe.',
    'assets/water.png',
    5,
  ),
  _MoodTask(
    'connect',
    'Reach Out to Someone',
    'Send a kind message to a friend or family member. Social connection is one of the strongest predictors of long-term mental wellbeing.',
    'assets/reading.png',
    15,
  ),
  _MoodTask(
    'meal',
    'Prepare a Healthy Meal',
    'What you eat directly shapes your mood via the gut-brain axis. Prepare something colourful and nutritious — even a simple salad counts.',
    'assets/meditation.png',
    20,
  ),
];

const _moods = [
  _Mood('Terrible', 'assets/terrible.png'),
  _Mood('Bad', 'assets/bad.png'),
  _Mood('Okay', 'assets/okay.png'),
  _Mood('Good', 'assets/good.png'),
  _Mood('Excellent', 'assets/excellent.png'),
];

class _MoodTask {
  final String id;
  final String title;
  final String description;
  final String asset;
  final int points;
  const _MoodTask(
    this.id,
    this.title,
    this.description,
    this.asset,
    this.points,
  );
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

  const HomeScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int? _selectedMood;
  bool _sidebarOpen = false;

  List<_MoodTask> _todayTasks = [];
  List<bool> _completedStates = [false, false, false];
  int _taskPoints = 0; // points from task completions only
  int _moodScore = 0; // combined: _taskPoints + calendar mood/activity score

  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadTodayTasks();
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
      // New day — pick 3 fresh random tasks
      final all = List.generate(_taskPool.length, (i) => i)..shuffle();
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
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _todayTasks = indices.map((i) => _taskPool[i]).toList();
        _completedStates = completed;
        _taskPoints = taskPoints;
        _moodScore = taskPoints + moodActivityScore;
      });
      _entranceCtrl.forward(from: 0);
    }
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
    _syncScoreToDb(today, newTaskPoints);
  }

  Future<void> _undoTask(int index) async {
    if (!_completedStates[index]) return;
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final newTaskPoints =
        (_taskPoints - _todayTasks[index].points).clamp(0, 9999) as int;
    final newMoodScore =
        (_moodScore - _todayTasks[index].points).clamp(0, 9999) as int;
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
    _syncScoreToDb(today, newTaskPoints);
  }

  void _syncScoreToDb(String dateKey, int taskScore) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      await http.post(
        Uri.parse('https://moodiary-production.up.railway.app/api/moods'),
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
    await prefs.remove('companion_id');
    await prefs.remove('companion_name');
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                task.asset,
                width: 80,
                height: 80,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.task_alt, size: 60, color: _kPurple),
              ),
              const SizedBox(height: 16),
              Text(
                task.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
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
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF3F0FB),
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
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
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
                                foregroundColor: const Color(0xFF888888),
                                side: const BorderSide(
                                  color: Color(0xFFDDDDDD),
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
    return Scaffold(
      backgroundColor: _kBg,
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
                          const Text(
                            "Today's Task",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _kDark,
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
                      _MoodScoreCard(score: _moodScore),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'How are you today?',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: _kDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(_moods.length, (i) {
                                final mood = _moods[i];
                                final selected = _selectedMood == i;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedMood = i),
                                  child: AnimatedScale(
                                    scale: selected ? 1.2 : 1.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Column(
                                      children: [
                                        Image.asset(
                                          mood.asset,
                                          width: 44,
                                          height: 44,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                Icons.sentiment_neutral,
                                                size: 44,
                                                color: _kSubtle,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          mood.label,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: selected
                                                ? _kPurple
                                                : _kSubtle,
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
              child: Container(color: Colors.black54),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: _sidebarOpen ? 0 : -280,
            top: 0,
            bottom: 0,
            width: 260,
            child: _Sidebar(
              userName: widget.userName,
              onClose: () => setState(() => _sidebarOpen = false),
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
      bottomNavigationBar: _BottomNav(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String formattedDate;
  final String greeting;
  final String companionAsset;
  final String companionName;
  final VoidCallback onHamburger;
  final VoidCallback onCompanionTap;

  const _Header({
    required this.formattedDate,
    required this.greeting,
    required this.companionAsset,
    required this.companionName,
    required this.onHamburger,
    required this.onCompanionTap,
  });

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(width: 48),
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
                          color: Colors.white,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Text(
                          '$greeting\nReady to take care of yourself today? Tap on me to talk!',
                          style: const TextStyle(
                            color: _kDark,
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
                          color: const Color(0xFFFEF08A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
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
                            errorBuilder: (_, __, ___) => const Icon(
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
    return TapScale(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: completed ? 0.65 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Image.asset(
                task.asset,
                width: 48,
                height: 48,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.task_alt, size: 48, color: _kSubtle),
              ),
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
                        color: _kDark,
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
                      style: const TextStyle(fontSize: 12, color: _kSubtle),
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
                        color: const Color(0xFFF3F0FB),
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
  const _MoodScoreCard({required this.score});

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF3F0FB), Color(0xFFEDE9FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPurple.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🌟 Mood Score',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _kDark,
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
                      color: _statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor.withOpacity(0.5)),
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
          Text(_message, style: const TextStyle(fontSize: 12, color: _kSubtle)),
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
        Icons.calendar_month_outlined,
        'Calendar',
        onTap: () {
          Navigator.of(context).push(
            FadeSlideRoute(
              page: CalendarScreen(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
              ),
            ),
          );
        },
      ),
      _NavItem(Icons.book_outlined, 'Journal', onTap: () {}),
      _NavItem(Icons.home_rounded, 'Home', active: true, onTap: () {}),
      _NavItem(Icons.chat_bubble_outline, 'Forums', onTap: () {}),
      _NavItem(Icons.folder_outlined, 'Resources', onTap: () {}),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                      color: item.active ? _kPurple : _kSubtle,
                      size: 26,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: item.active ? _kPurple : _kSubtle,
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

// ─── Sidebar ──────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final String userName;
  final VoidCallback onClose;
  final VoidCallback onChangeCompanion;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.userName,
    required this.onClose,
    required this.onChangeCompanion,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 16,
      child: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'moodiary',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _kPurple,
                    ),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: onClose),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Hi, $userName!',
                style: const TextStyle(color: _kSubtle, fontSize: 13),
              ),
              const SizedBox(height: 24),
              const _SidebarItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: true,
              ),
              const _SidebarItem(
                icon: Icons.calendar_month_outlined,
                label: 'Calendar',
              ),
              const _SidebarItem(icon: Icons.book_outlined, label: 'Journal'),
              const _SidebarItem(
                icon: Icons.chat_bubble_outline,
                label: 'Forums',
              ),
              const _SidebarItem(
                icon: Icons.folder_outlined,
                label: 'Resources',
              ),
              TapScale(
                onTap: onChangeCompanion,
                child: const _SidebarItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Change Companion',
                ),
              ),
              const Spacer(),
              TapScale(
                onTap: onLogout,
                child: const Row(
                  children: [
                    Icon(Icons.logout, color: _kSubtle, size: 22),
                    SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(color: _kSubtle, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? _kPurple : const Color(0xFF888888),
            size: 22,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: active ? _kPurple : const Color(0xFF444444),
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
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

  static const _kBaseUrl = 'https://moodiary-production.up.railway.app';

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
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // ── Handle bar
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F0FB),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset(
                      widget.companionAsset,
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.sentiment_satisfied_alt,
                        color: _kSubtle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  widget.companionName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _kSubtle),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Messages
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => TapScale(
                  onTap: () => _send(_prompts[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F0FB),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      _prompts[i],
                      style: const TextStyle(color: _kPurple, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),

          // ── Input row
          const Divider(height: 1),
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
                    decoration: InputDecoration(
                      hintText: 'Say something…',
                      hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
                      filled: true,
                      fillColor: const Color(0xFFF5F5F5),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TapScale(
                  onTap: () => _send(_input.text),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: _kPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? _kPurple : const Color(0xFFF3F0FB),
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
            color: isUser ? Colors.white : _kDark,
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FB),
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
              builder: (_, __) {
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
                    decoration: const BoxDecoration(
                      color: _kSubtle,
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
