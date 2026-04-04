import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/local_notifications_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/theme_controller.dart';
import '../../utils/avatar_file_picker.dart';
import '../../utils/avatar_utils.dart';
import '../../utils/streak_utils.dart';
import '../../utils/transitions.dart';
import '../../utils/user_cache.dart';
import '../../widgets/app_sidebar.dart';
import '../calendar/calendar_screen.dart';
import '../companion/companion_screen.dart';
import '../forums/forums_screen.dart';
import '../friends/friends_screen.dart';
import '../home/home_screen.dart';
import '../journal/journal_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import 'mbti_test_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Future<Map<String, dynamic>> _profileFuture = Future.value(const {});
  late String _userId;
  late String _authToken;
  bool _sidebarOpen = false;
  bool _isEditing = false;
  String _currentUserName = 'Friend';
  int _companionId = 1;
  String _companionName = 'Companion';
  int _streakCount = 0;
  String? _selectedAvatarDataUrl;
  String? _currentAvatarUrl;
  int _todayMoodScore = 0;
  String _currentMoodLabel = 'No mood logged';
  String _currentMoodAsset = 'assets/okay.png';

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
    _authToken = prefs.getString('token') ?? '';
    final storedName = prefs.getString('user_name')?.trim();
    if (storedName != null && storedName.isNotEmpty) {
      _currentUserName = storedName;
    }
    _companionId = prefs.getInt('companion_id') ?? 1;
    _companionName = prefs.getString('companion_name') ?? 'Companion';
    _streakCount = await StreakUtils.refreshFromMoodCache(prefs);

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final scoreKey = 'mood_score_$dateKey';
    _todayMoodScore = prefs.getInt(scoreKey) ?? 0;

    final rawCache = prefs.getString('mood_logs_cache');
    if (rawCache != null) {
      try {
        final decoded = jsonDecode(rawCache) as List<dynamic>;
        final index = decoded.indexWhere((e) => e['dateKey'] == dateKey);
        if (index >= 0) {
          final todayLog = decoded[index] as Map<String, dynamic>;
          final rawScore = todayLog['score'];
          if (rawScore is num) {
            _todayMoodScore = rawScore.round();
          }

          final moodLevel = todayLog['moodLevel'] as int?;
          if (moodLevel != null && moodLevel >= 1 && moodLevel <= 5) {
            const moodLabels = ['Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];
            const moodAssets = [
              'assets/terrible.png',
              'assets/bad.png',
              'assets/okay.png',
              'assets/good.png',
              'assets/excellent.png',
            ];
            _currentMoodLabel = moodLabels[moodLevel - 1];
            _currentMoodAsset = moodAssets[moodLevel - 1];
          }
        }
      } catch (_) {
        // Ignore malformed cache and keep defaults.
      }
    }

    final cachedBundle = await _loadCachedProfileBundle();

    if (!mounted) return;
    if (cachedBundle != null) {
      setState(() {
        _profileFuture = Future.value(cachedBundle);
      });
      _refreshProfileBundleInBackground();
    } else {
      setState(() {
        _profileFuture = _loadProfileBundle();
      });
    }
  }

  Future<Map<String, dynamic>> _loadProfileBundle() async {
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('user_name');
    final results = await Future.wait<dynamic>([
      AuthService.instance.getUserProfile(userId: _userId),
      AuthService.instance.getMyForumPosts(
        authToken: _authToken,
        userName: userName,
      ),
    ]);

    return {
      'profile': results[0] as Map<String, dynamic>,
      'posts': results[1] as List<Map<String, dynamic>>,
    };
  }

  Future<Map<String, dynamic>?> _loadCachedProfileBundle() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCache = prefs.getString(UserCache.profileBundleCacheKey);
    if (rawCache == null || rawCache.isEmpty) return null;

    try {
      final decoded = jsonDecode(rawCache);
      if (decoded is Map<String, dynamic>) {
        final profile = decoded['profile'];
        final posts = decoded['posts'];
        if (profile is Map<String, dynamic> && posts is List) {
          return {
            'profile': profile,
            'posts': posts.cast<Map<String, dynamic>>(),
          };
        }
      }
    } catch (_) {
      // Ignore malformed cache.
    }

    return null;
  }

  Future<void> _refreshProfileBundleInBackground() async {
    try {
      final bundle = await _loadProfileBundle();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UserCache.profileBundleCacheKey,
        jsonEncode(bundle),
      );
      if (!mounted) return;
      setState(() {
        _profileFuture = Future.value(bundle);
      });
    } catch (_) {
      // Keep the cached view if the refresh fails.
    }
  }

  Future<void> _saveProfile() async {
    try {
      final updated = await AuthService.instance.updateUserProfile(
        userId: _userId,
        authToken: _authToken,
        name: _nameController.text,
        email: _emailController.text,
        bio: _bioController.text,
        avatarUrl: _selectedAvatarDataUrl,
      );

      final updatedUser = updated['user'] as Map<String, dynamic>?;
      final updatedAvatarUrl = updatedUser?['avatarUrl'] as String?;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());
      _currentUserName = _nameController.text.trim();
      if (updatedAvatarUrl != null && updatedAvatarUrl.isNotEmpty) {
        _currentAvatarUrl = updatedAvatarUrl;
        await prefs.setString('user_avatar_url', updatedAvatarUrl);
      } else if (_selectedAvatarDataUrl != null &&
          _selectedAvatarDataUrl!.isNotEmpty) {
        await prefs.setString('user_avatar_url', _selectedAvatarDataUrl!);
      } else if (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty) {
        await prefs.setString('user_avatar_url', _currentAvatarUrl!);
      }

      final existingCache = await _loadCachedProfileBundle();
      if (existingCache != null) {
        final profile = existingCache['profile'] as Map<String, dynamic>;
        final user = Map<String, dynamic>.from(
          profile['user'] as Map<String, dynamic>? ?? const {},
        );
        user['name'] = _nameController.text.trim();
        user['email'] = _emailController.text.trim();
        user['bio'] = _bioController.text.trim();
        if (updatedAvatarUrl != null && updatedAvatarUrl.isNotEmpty) {
          user['avatarUrl'] = updatedAvatarUrl;
        } else if (_selectedAvatarDataUrl != null &&
            _selectedAvatarDataUrl!.isNotEmpty) {
          user['avatarUrl'] = _selectedAvatarDataUrl;
        } else if (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty) {
          user['avatarUrl'] = _currentAvatarUrl;
        }
        profile['user'] = user;
        await prefs.setString(
          UserCache.profileBundleCacheKey,
          jsonEncode(existingCache),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      setState(() {
        _isEditing = false;
        _selectedAvatarDataUrl = null;
        _profileFuture = _loadProfileBundle();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _openScreen(Widget page) {
    setState(() => _sidebarOpen = false);
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_name');
    await prefs.remove('user_id');
    RealtimeNotifications.instance.disconnect();
    await ThemeController.instance.resetToDefault();
    await LocalNotificationsService.instance.cancelAllScheduled();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(page: const OnboardingScreen()),
      (_) => false,
    );
  }

  Future<void> _pickAvatarImage() async {
    try {
      final bytes = await pickAvatarBytes();
      if (bytes == null) return;

      final dataUrl = dataUrlFromImageBytes(bytes, mimeType: 'image/jpeg');
      if (dataUrl == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not process selected image.')),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _selectedAvatarDataUrl = dataUrl;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not select image: $e')));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => setState(() => _sidebarOpen = true),
        ),
        title: const Text('User Profile'),
        elevation: 0,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _isEditing = false),
            ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final bundle = snapshot.data;
              final userData =
                  bundle?['profile']?['user'] as Map<String, dynamic>?;
              if (userData == null) {
                return const Center(child: Text('Profile not found'));
              }

              final posts =
                  (bundle?['posts'] as List<Map<String, dynamic>>? ?? const [])
                      .where(
                        (p) =>
                            p['isMine'] == true ||
                            p['authorName'] == userData['name'],
                      )
                      .take(3)
                      .toList();

              _currentAvatarUrl = userData['avatarUrl'] as String?;
              final displayedAvatarUrl =
                  _selectedAvatarDataUrl ?? _currentAvatarUrl;

              if (!_isEditing &&
                  _nameController.text.isEmpty &&
                  userData['name'] != null) {
                _nameController.text = userData['name'] as String;
                _emailController.text = userData['email'] as String? ?? '';
                _bioController.text = userData['bio'] as String? ?? '';
              }

              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 128),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 48,
                                    backgroundImage: avatarImageProvider(
                                      displayedAvatarUrl,
                                    ),
                                    child:
                                        avatarImageProvider(
                                              displayedAvatarUrl,
                                            ) ==
                                            null
                                        ? const Icon(Icons.person, size: 44)
                                        : null,
                                  ),
                                  if (_isEditing)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: InkWell(
                                        onTap: _pickAvatarImage,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: cs.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.photo_camera_outlined,
                                            size: 16,
                                            color: cs.onPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                (userData['name'] as String? ?? 'NAME')
                                    .toUpperCase(),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'WHAT I\'M FEELING RIGHT NOW...',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _MoodMini(asset: _currentMoodAsset),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _currentMoodLabel,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 120,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mood Score',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$_todayMoodScore',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: cs.primary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.local_fire_department_rounded,
                                color: Color(0xFFEA580C),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Current streak: $_streakCount ${_streakCount == 1 ? 'day' : 'days'}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.psychology_outlined),
                                  const SizedBox(width: 8),
                                  Text(
                                    'MBTI Personality',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                (userData['mbtiLatestType'] as String?) ??
                                    'No MBTI result yet',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: () async {
                                    final completed =
                                        await Navigator.of(context).push<bool>(
                                          FadeSlideRoute(
                                            page: MbtiTestScreen(
                                              userName: _currentUserName,
                                            ),
                                          ),
                                        );
                                    if (completed == true && mounted) {
                                      await _refreshProfileBundleInBackground();
                                    }
                                  },
                                  child: Text(
                                    (userData['mbtiLatestType'] as String?) ==
                                            null
                                        ? 'Take MBTI Test'
                                        : 'Retake MBTI Test',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Public Posts (Forums)',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        if (posts.isEmpty)
                          const _SimpleInfoCard(
                            title: 'Posts',
                            subtitle: 'No public forum posts yet.',
                            leading: Icons.chat_bubble_outline,
                          )
                        else
                          ...posts.map(
                            (p) => _SimpleInfoCard(
                              title: (p['title'] as String?) ?? 'Untitled Post',
                              subtitle: (p['content'] as String?) ?? '',
                              leading: Icons.forum_outlined,
                            ),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          'Name',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (_isEditing)
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: 'Your name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(userData['name'] as String? ?? 'N/A'),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'Email',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (_isEditing)
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText: 'your.email@example.com',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                userData['email'] as String? ?? 'N/A',
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'Bio',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (_isEditing)
                          TextField(
                            controller: _bioController,
                            maxLines: 4,
                            maxLength: 500,
                            keyboardType: TextInputType.multiline,
                            decoration: InputDecoration(
                              hintText:
                                  'Tell us about yourself... Emojis are welcome 😊',
                              helperText: 'You can use emojis in your bio.',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                userData['bio'] as String? ?? 'No bio',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Member Since',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    Text(
                                      userData['createdAt'] != null
                                          ? DateTime.parse(
                                              userData['createdAt'] as String,
                                            ).toString().split(' ')[0]
                                          : 'N/A',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  if (_isEditing)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 14,
                      child: SafeArea(
                        top: false,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text('Save Changes'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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
            child: AppSidebar(
              userName: _currentUserName,
              activeSection: SidebarSection.userProfile,
              onClose: () => setState(() => _sidebarOpen = false),
              onNavigateHome: () => _openScreen(
                HomeScreen(
                  userName: _currentUserName,
                  companionId: _companionId,
                  companionName: _companionName,
                  initialProfileAvatarUrl:
                      _selectedAvatarDataUrl ?? _currentAvatarUrl,
                ),
              ),
              onNavigateUserProfile: () => setState(() => _sidebarOpen = false),
              onNavigateCalendar: () => _openScreen(
                CalendarScreen(
                  userName: _currentUserName,
                  companionId: _companionId,
                  companionName: _companionName,
                ),
              ),
              onNavigateJournal: () => _openScreen(
                JournalScreen(
                  userName: _currentUserName,
                  companionId: _companionId,
                  companionName: _companionName,
                ),
              ),
              onNavigateFriends: () => _openScreen(
                FriendsScreen(
                  userName: _currentUserName,
                  companionId: _companionId,
                  companionName: _companionName,
                ),
              ),
              onNavigateForums: () => _openScreen(
                ForumsScreen(
                  userName: _currentUserName,
                  companionId: _companionId,
                  companionName: _companionName,
                ),
              ),
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: _currentUserName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: _currentUserName)),
              onLogout: () {
                setState(() => _sidebarOpen = false);
                _logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleInfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? leading;

  const _SimpleInfoCard({
    required this.title,
    required this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    final subtleColor = Theme.of(context).textTheme.bodySmall?.color;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[
              Icon(leading, size: 18, color: subtleColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textColor),
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

class _MoodMini extends StatelessWidget {
  final String asset;

  const _MoodMini({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.sentiment_satisfied_alt, size: 16),
        ),
      ),
    );
  }
}
