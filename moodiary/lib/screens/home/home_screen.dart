import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../onboarding/onboarding_screen.dart';
import '../companion/companion_screen.dart';

const _kPurple = Color(0xFFA076F9);
const _kLightPurple = Color(0xFFD8B4F8);
const _kDark = Color(0xFF3D3B40);
const _kBg = Color(0xFFF7F5F2);
const _kCardBg = Colors.white;
const _kSubtle = Color(0xFF8A8A8D);

const _tasks = [
  _Task(
    'Drink Enough Water',
    'Most experts suggest that you drink five to eight glasses of water.',
    'assets/water.png',
    false,
  ),
  _Task(
    'Keep Reading',
    'Reading helps a great deal in building confidence and reduces stress.',
    'assets/reading.png',
    true,
  ),
  _Task(
    'Try Meditation',
    'According to Harvard Health, daily meditations can help with your mental and emotional health.',
    'assets/meditation.png',
    true,
  ),
];

const _moods = [
  _Mood('Terrible', 'assets/terrible.png'),
  _Mood('Bad', 'assets/bad.png'),
  _Mood('Okay', 'assets/okay.png'),
  _Mood('Good', 'assets/good.png'),
  _Mood('Excellent', 'assets/excellent.png'),
];

class _Task {
  final String title;
  final String description;
  final String asset;
  final bool completed;
  const _Task(this.title, this.description, this.asset, this.completed);
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

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedMood;
  bool _sidebarOpen = false;

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
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        (_) => false,
      );
    }
  }

  void _showTaskDetail(_Task task) {
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
                ),
              ),
              const SizedBox(height: 10),
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
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPurple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: const Text('Got it!'),
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
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text(
                                '3',
                                style: TextStyle(
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
                      ..._tasks.map(
                        (task) => _TaskCard(
                          task: task,
                          onTap: () => _showTaskDetail(task),
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
                  MaterialPageRoute(
                    builder: (_) => CompanionScreen(userName: widget.userName),
                  ),
                );
              },
              onLogout: _logout,
            ),
          ),
        ],
      ),
      bottomNavigationBar: const _BottomNav(),
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
                    GestureDetector(
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
  final _Task task;
  final VoidCallback onTap;
  const _TaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kDark,
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
            if (task.completed)
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF4ADE80),
                size: 28,
              )
            else
              const Row(
                children: [
                  Text(
                    '❤️ +1',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, color: _kPurple, size: 16),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom Nav ───────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(Icons.calendar_month_outlined, 'Calendar'),
      _NavItem(Icons.book_outlined, 'Journal'),
      _NavItem(Icons.home_rounded, 'Home', active: true),
      _NavItem(Icons.chat_bubble_outline, 'Forums'),
      _NavItem(Icons.folder_outlined, 'Resources'),
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
              (item) => GestureDetector(
                onTap: () {},
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
  const _NavItem(this.icon, this.label, {this.active = false});
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
              GestureDetector(
                onTap: onChangeCompanion,
                child: const _SidebarItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Change Companion',
                ),
              ),
              const Spacer(),
              GestureDetector(
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
class _CompanionChat extends StatelessWidget {
  final String companionName;
  final String companionAsset;
  const _CompanionChat({
    required this.companionName,
    required this.companionAsset,
  });

  @override
  Widget build(BuildContext context) {
    final prompts = [
      'Tell me a motivational quote.',
      'What should I do today?',
      'I am feeling anxious.',
      'Help me calm down.',
    ];
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
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
                      companionAsset,
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
                  companionName,
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
          Expanded(
            child: Center(
              child: Text(
                'Hi! I\'m $companionName. How can I help you today?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _kSubtle, fontSize: 14),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: prompts
                  .map(
                    (p) => GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          p,
                          style: const TextStyle(color: _kDark, fontSize: 13),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
