import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';
import '../../utils/transitions.dart';

const _kPurple = Color(0xFFA076F9);
const _kDark = Color(0xFF3D3B40);
const _kSubtle = Color(0xFF8A8A8D);
const _kHeaderBg = Color(0xFFF3E8FF);
const _kBaseUrl = 'https://moodiary-production.up.railway.app';

// ─── Activity data ────────────────────────────────────────────────────────────
class _Activity {
  final String name;
  final int score;
  final String category;
  const _Activity(this.name, this.score, this.category);
}

const _allActivities = [
  _Activity('Work', -1, 'Challenges'),
  _Activity('Exercise', 2, 'Health'),
  _Activity('Yoga', 3, 'Health'),
  _Activity('Meditation', 3, 'Health'),
  _Activity('Good Sleep', 2, 'Health'),
  _Activity('Ate Healthy', 1, 'Health'),
  _Activity('Drank Water', 1, 'Health'),
  _Activity('Social', 2, 'Social'),
  _Activity('Family Time', 2, 'Social'),
  _Activity('Date Night', 3, 'Social'),
  _Activity('Party', 1, 'Social'),
  _Activity('Deep Talk', 2, 'Social'),
  _Activity('New Friend', 2, 'Social'),
  _Activity('Hobby', 2, 'Hobbies'),
  _Activity('Creative', 2, 'Hobbies'),
  _Activity('Gaming', 1, 'Hobbies'),
  _Activity('Reading', 1, 'Hobbies'),
  _Activity('Movies', 1, 'Hobbies'),
  _Activity('Music', 1, 'Hobbies'),
  _Activity('Cooking', 2, 'Hobbies'),
  _Activity('Tidy Up', 1, 'Productivity'),
  _Activity('Finished Task', 2, 'Productivity'),
  _Activity('Planned Day', 1, 'Productivity'),
  _Activity('Studying', 1, 'Productivity'),
  _Activity('Self-care', 2, 'Relaxation'),
  _Activity('Rest', 1, 'Relaxation'),
  _Activity('Outdoors', 2, 'Relaxation'),
  _Activity('Journaling', 2, 'Relaxation'),
  _Activity('Bath', 1, 'Relaxation'),
  _Activity('Stressed', -2, 'Challenges'),
  _Activity('Anxious', -2, 'Challenges'),
  _Activity('Argument', -3, 'Challenges'),
  _Activity('Bad Sleep', -2, 'Challenges'),
  _Activity('Sick', -2, 'Challenges'),
  _Activity('Busy Day', -1, 'Challenges'),
  _Activity('Sad', -2, 'Challenges'),
];

const _commonActivityNames = [
  'Exercise',
  'Social',
  'Work',
  'Hobby',
  'Rest',
  'Studying',
];

final _activityScoreMap = Map.fromEntries(
  _allActivities.map((a) => MapEntry(a.name, a.score)),
);

// ─── MoodLog model ────────────────────────────────────────────────────────────
class _MoodLog {
  final String dateKey;
  final int moodLevel;
  final List<String> activities;
  final int score;
  _MoodLog({
    required this.dateKey,
    required this.moodLevel,
    required this.activities,
    required this.score,
  });

  factory _MoodLog.fromJson(Map<String, dynamic> j) => _MoodLog(
    dateKey: j['dateKey'] as String,
    moodLevel: j['moodLevel'] as int,
    activities: List<String>.from(j['activities'] ?? []),
    score: (j['score'] ?? 0) as int,
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
Color _dotColor(int score) {
  if (score >= 9) return const Color(0xFF10B981);
  if (score >= 6) return const Color(0xFF84CC16);
  if (score >= 3) return const Color(0xFFFACC15);
  if (score >= 0) return const Color(0xFFF97316);
  return const Color(0xFFEF4444);
}

String _toDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

// ─── CalendarScreen ───────────────────────────────────────────────────────────
class CalendarScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  const CalendarScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, _MoodLog> _logs = {};
  bool _loading = true;
  String? _token;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    // Load from local cache instantly, then refresh from DB in background
    _loadFromCache(prefs);
    _fetchLogs(prefs);
  }

  void _loadFromCache(SharedPreferences prefs) {
    final cached = prefs.getString('mood_logs_cache');
    if (cached == null) return;
    try {
      final List<dynamic> data = jsonDecode(cached);
      setState(() {
        _logs.clear();
        for (final d in data) {
          final log = _MoodLog.fromJson(d as Map<String, dynamic>);
          _logs[log.dateKey] = log;
        }
        _loading = false;
      });
    } catch (_) {}
  }

  Future<void> _fetchLogs(SharedPreferences prefs) async {
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/api/moods'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final List<dynamic> data = jsonDecode(resp.body);
      // Save to local cache
      await prefs.setString('mood_logs_cache', resp.body);
      if (mounted) {
        setState(() {
          _logs.clear();
          for (final d in data) {
            final log = _MoodLog.fromJson(d as Map<String, dynamic>);
            _logs[log.dateKey] = log;
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLog(
    String dateKey,
    int moodLevel,
    List<String> activities,
  ) async {
    final score =
        moodLevel +
        activities.fold<int>(0, (sum, a) => sum + (_activityScoreMap[a] ?? 0));
    setState(() {
      _logs[dateKey] = _MoodLog(
        dateKey: dateKey,
        moodLevel: moodLevel,
        activities: activities,
        score: score,
      );
    });
    // Update local cache immediately
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'mood_logs_cache',
      jsonEncode(
        _logs.values
            .map(
              (l) => {
                'dateKey': l.dateKey,
                'moodLevel': l.moodLevel,
                'activities': l.activities,
                'score': l.score,
              },
            )
            .toList(),
      ),
    );
    if (_token == null) return;
    try {
      await http.post(
        Uri.parse('$_kBaseUrl/api/moods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'dateKey': dateKey,
          'moodLevel': moodLevel,
          'activities': activities,
          'score': score,
        }),
      );
    } catch (_) {}
  }

  void _openLogModal(DateTime day) {
    final key = _toDateKey(day);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogModal(
        day: day,
        existing: _logs[key],
        onSave: (moodLevel, activities) => _saveLog(key, moodLevel, activities),
      ),
    );
  }

  List<_MoodLog> get _trendLogs {
    final now = DateTime.now();
    final result = <_MoodLog>[];
    for (int i = 29; i >= 0; i--) {
      final key = _toDateKey(now.subtract(Duration(days: i)));
      if (_logs.containsKey(key)) result.add(_logs[key]!);
    }
    return result;
  }

  String get _formattedDate {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kHeaderBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPurple),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCalendar(),
                          const SizedBox(height: 28),
                          _buildTrendChart(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: _kDark,
                    size: 20,
                  ),
                ),
                Text(
                  _formattedDate,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 24),
              ],
            ),
            const SizedBox(height: 12),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
                children: [
                  TextSpan(text: 'M'),
                  TextSpan(
                    text: 'oo',
                    style: TextStyle(color: Color(0xFF60A5FA)),
                  ),
                  TextSpan(text: 'd '),
                  TextSpan(
                    text: 'Calendar',
                    style: TextStyle(
                      color: _kPurple,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Log your moods and activities daily.',
              style: TextStyle(color: Color(0xFF888888), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── Calendar ─────────────────────────────────────────────────────────────────
  Widget _buildCalendar() {
    final year = _displayMonth.year;
    final month = _displayMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = firstDay.weekday % 7; // Sun=0

    final today = DateTime.now();
    final todayKey = _toDateKey(today);

    const weekDays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Column(
      children: [
        // Month navigation
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: _kDark),
              onPressed: () =>
                  setState(() => _displayMonth = DateTime(year, month - 1)),
            ),
            Text(
              '${_monthNames[month - 1]} $year',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: _kDark,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: _kDark),
              onPressed: () =>
                  setState(() => _displayMonth = DateTime(year, month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Weekday headers
        Row(
          children: weekDays
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _kSubtle,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        // Days grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.85,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: firstWeekday + daysInMonth,
          itemBuilder: (_, i) {
            if (i < firstWeekday) return const SizedBox();
            final day = i - firstWeekday + 1;
            final date = DateTime(year, month, day);
            final key = _toDateKey(date);
            final log = _logs[key];
            final isToday = key == todayKey;
            final isFuture = date.isAfter(today);

            return GestureDetector(
              onTap: isFuture ? null : () => _openLogModal(date),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isToday ? _kPurple : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isToday
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isToday
                              ? Colors.white
                              : isFuture
                              ? const Color(0xFFCCCCCC)
                              : _kDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 7,
                    child: log != null
                        ? Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _dotColor(log.score),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Legend
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: const [
            _LegendDot(color: Color(0xFF10B981), label: 'High'),
            _LegendDot(color: Color(0xFF84CC16), label: 'Good'),
            _LegendDot(color: Color(0xFFFACC15), label: 'Moderate'),
            _LegendDot(color: Color(0xFFF97316), label: 'Low'),
            _LegendDot(color: Color(0xFFEF4444), label: 'Very Low'),
          ],
        ),
      ],
    );
  }

  // ── Trend Chart ───────────────────────────────────────────────────────────────
  Widget _buildTrendChart() {
    final trendLogs = _trendLogs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mood Trend',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: _kDark,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(20),
          ),
          child: trendLogs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No mood logs yet.\nTap a date to start!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _kSubtle, fontSize: 14),
                    ),
                  ),
                )
              : SizedBox(
                  height: 160,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 3,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0xFFE5E7EB),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 1,
                            getTitlesWidget: (value, _) {
                              final i = value.toInt();
                              if (i < 0 || i >= trendLogs.length) {
                                return const SizedBox();
                              }
                              // Only label every few points to avoid crowding
                              final total = trendLogs.length;
                              if (total > 10 &&
                                  i != 0 &&
                                  i != total - 1 &&
                                  i % ((total / 4).ceil()) != 0) {
                                return const SizedBox();
                              }
                              final parts = trendLogs[i].dateKey.split('-');
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${parts[1]}/${parts[2]}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: _kSubtle,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      maxY: 12,
                      lineBarsData: [
                        LineChartBarData(
                          spots: trendLogs
                              .asMap()
                              .entries
                              .map(
                                (e) => FlSpot(
                                  e.key.toDouble(),
                                  e.value.score.toDouble(),
                                ),
                              )
                              .toList(),
                          isCurved: true,
                          color: _kPurple,
                          barWidth: 3,
                          dotData: FlDotData(
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                                  radius: 4,
                                  color: _kPurple,
                                  strokeWidth: 0,
                                ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: _kPurple.withOpacity(0.08),
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

  // ── Bottom Nav ────────────────────────────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0), width: 1.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavBtn(
            icon: Icons.calendar_month_outlined,
            label: 'Calendar',
            active: true,
            onTap: () {},
          ),
          _NavBtn(icon: Icons.book_outlined, label: 'Journal', onTap: () {}),
          _NavBtn(
            icon: Icons.home_rounded,
            label: 'Home',
            onTap: () => Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(
                page: HomeScreen(
                  userName: widget.userName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              (_) => false,
            ),
          ),
          _NavBtn(
            icon: Icons.chat_bubble_outline,
            label: 'Forums',
            onTap: () {},
          ),
          _NavBtn(
            icon: Icons.folder_outlined,
            label: 'Resources',
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

// ─── Legend dot ───────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: _kSubtle)),
      ],
    );
  }
}

// ─── Bottom nav button ────────────────────────────────────────────────────────
class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavBtn({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? _kPurple : _kSubtle, size: 26),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: active ? _kPurple : _kSubtle,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Log Modal ────────────────────────────────────────────────────────────────
class _LogModal extends StatefulWidget {
  final DateTime day;
  final _MoodLog? existing;
  final Function(int moodLevel, List<String> activities) onSave;
  const _LogModal({required this.day, this.existing, required this.onSave});

  @override
  State<_LogModal> createState() => _LogModalState();
}

class _LogModalState extends State<_LogModal> {
  int _moodLevel = 0;
  late Set<String> _selectedActivities;
  bool _showAll = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _moodLabels = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];
  static const _moodAssets = [
    'assets/terrible.png',
    'assets/bad.png',
    'assets/okay.png',
    'assets/good.png',
    'assets/excellent.png',
  ];

  @override
  void initState() {
    super.initState();
    _moodLevel = widget.existing?.moodLevel ?? 0;
    _selectedActivities = Set.from(widget.existing?.activities ?? []);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _score =>
      _moodLevel +
      _selectedActivities.fold<int>(
        0,
        (sum, a) => sum + (_activityScoreMap[a] ?? 0),
      );

  Color get _scoreBarColor {
    final pct = (_score / 12).clamp(0.0, 1.0);
    if (pct > 0.75) return const Color(0xFF4ADE80);
    if (pct > 0.5) return const Color(0xFFA3E635);
    if (pct > 0.25) return const Color(0xFFFBBF24);
    return const Color(0xFFF87171);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(child: _showAll ? _buildAllView() : _buildMainView()),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    final monthName = _monthNames[widget.day.month - 1];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Log for $monthName ${widget.day.day}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kDark,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'How are you today?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 12),
          // Mood emoji row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(5, (i) {
              final selected = _moodLevel == i + 1;
              return GestureDetector(
                onTap: () => setState(() => _moodLevel = i + 1),
                child: AnimatedScale(
                  scale: selected ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected ? _kPurple : Colors.transparent,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(50),
                          color: selected
                              ? const Color(0xFFF3E8FF)
                              : Colors.transparent,
                        ),
                        child: Image.asset(
                          _moodAssets[i],
                          width: 44,
                          height: 44,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.sentiment_neutral,
                            size: 44,
                            color: _kSubtle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _moodLabels[i],
                        style: TextStyle(
                          fontSize: 10,
                          color: selected ? _kPurple : _kSubtle,
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
          const SizedBox(height: 20),
          const Text(
            'What did you do today?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._commonActivityNames.map((name) {
                final sel = _selectedActivities.contains(name);
                return _ActivityChip(
                  name: name,
                  selected: sel,
                  onTap: () => setState(() {
                    if (sel) {
                      _selectedActivities.remove(name);
                    } else {
                      _selectedActivities.add(name);
                    }
                  }),
                );
              }),
              _ActivityChip(
                name: '+ More',
                selected: false,
                isMoreButton: true,
                onTap: () => setState(() => _showAll = true),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's mood score:",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _kDark,
                ),
              ),
              Text(
                '$_score',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _kPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (_score / 12).clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(_scoreBarColor),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: _kSubtle),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _moodLevel == 0
                      ? null
                      : () {
                          widget.onSave(
                            _moodLevel,
                            _selectedActivities.toList(),
                          );
                          Navigator.of(context).pop();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    disabledBackgroundColor: const Color(0xFFDDD6FE),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllView() {
    final Map<String, List<_Activity>> categories = {};
    for (final a in _allActivities) {
      if (a.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        categories.putIfAbsent(a.category, () => []).add(a);
      }
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'All Activities',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showAll = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                }),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    color: _kPurple,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search activities...',
              prefixIcon: const Icon(Icons.search, color: _kSubtle),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: categories.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _kSubtle,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value.map((a) {
                        final sel = _selectedActivities.contains(a.name);
                        return _ActivityChip(
                          name: a.name,
                          selected: sel,
                          onTap: () => setState(() {
                            if (sel) {
                              _selectedActivities.remove(a.name);
                            } else {
                              _selectedActivities.add(a.name);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Activity chip ────────────────────────────────────────────────────────────
class _ActivityChip extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final bool isMoreButton;
  const _ActivityChip({
    required this.name,
    required this.selected,
    required this.onTap,
    this.isMoreButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? _kPurple
              : isMoreButton
              ? const Color(0xFFE5E7EB)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? Colors.white
                : isMoreButton
                ? const Color(0xFF6B7280)
                : _kDark,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
