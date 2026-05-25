import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/local_notifications_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/avatar_file_picker.dart';
import '../../utils/avatar_utils.dart';
import '../../utils/streak_utils.dart';
import '../../utils/transitions.dart';
import '../../utils/user_cache.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_profile_popup.dart';
import '../calendar/calendar_screen.dart';
import '../companion/companion_screen.dart';
import '../app_shell.dart';
import '../journal/journal_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import 'mbti_test_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final ShellTabSelector? onShellTabSelected;
  final bool showTopNav;
  final ShellNavVisibilitySetter? onShellNavVisibilityChanged;

  const UserProfileScreen({
    super.key,
    this.onShellTabSelected,
    this.showTopNav = true,
    this.onShellNavVisibilityChanged,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Future<Map<String, dynamic>> _profileFuture = Future.value(const {});
  late String _userId;
  late String _authToken;
  bool _sidebarOpen = false;
  bool _headerCollapsed = false;
  bool _isEditing = false;
  bool _isProfilePublic = false;
  bool _savingProfileVisibility = false;
  bool _didHydrateProfileVisibility = false;
  String _currentUserName = 'Friend';
  int _companionId = 1;
  String _companionName = 'Companion';
  int _streakCount = 0;
  String? _selectedAvatarDataUrl;
  String? _currentAvatarUrl;
  int _todayMoodScore = 0;
  String _currentMoodLabel = 'No mood logged';
  String _currentMoodAsset = 'assets/okay.png';
  final Map<String, ImageProvider<Object>> _avatarImageCache = {};
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();

  ImageProvider<Object>? _cachedAvatarImage(String? source) {
    final trimmed = source?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final cached = _avatarImageCache[trimmed];
    if (cached != null) {
      return cached;
    }
    final created = avatarImageProvider(trimmed);
    if (created != null) {
      _avatarImageCache[trimmed] = created;
    }
    return created;
  }

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
    final profileFuture = AuthService.instance.getUserProfile(
      userId: _userId,
      authToken: _authToken,
    );
    final postsFuture = AuthService.instance
        .getMyForumPosts(authToken: _authToken, userName: userName)
        .catchError((_) => const <Map<String, dynamic>>[]);
    final mbtiFuture = AuthService.instance
        .getMbtiHistory(userId: _userId, authToken: _authToken, limit: 5)
        .then(
          (mbti) => (mbti['items'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>(),
        )
        .catchError((_) => const <Map<String, dynamic>>[]);

    final profile = await profileFuture;
    final posts = await postsFuture;
    final mbtiItems = await mbtiFuture;

    return {'profile': profile, 'posts': posts, 'mbtiHistory': mbtiItems};
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
        isProfilePublic: _isProfilePublic,
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
        user['isProfilePublic'] = _isProfilePublic;
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
        if (mounted) {
          setState(() {
            _profileFuture = Future.value(existingCache);
          });
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      setState(() {
        _isEditing = false;
        _selectedAvatarDataUrl = null;
      });
      unawaited(_refreshProfileBundleInBackground());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _updateProfileVisibility(bool value) async {
    if (_savingProfileVisibility) return;
    final previous = _isProfilePublic;
    setState(() {
      _isProfilePublic = value;
      _savingProfileVisibility = true;
    });

    try {
      await AuthService.instance.updateUserProfile(
        userId: _userId,
        authToken: _authToken,
        isProfilePublic: value,
      );

      final prefs = await SharedPreferences.getInstance();
      final existingCache = await _loadCachedProfileBundle();
      if (existingCache != null) {
        final profile = existingCache['profile'] as Map<String, dynamic>;
        final user = Map<String, dynamic>.from(
          profile['user'] as Map<String, dynamic>? ?? const {},
        );
        user['isProfilePublic'] = value;
        profile['user'] = user;
        await prefs.setString(
          UserCache.profileBundleCacheKey,
          jsonEncode(existingCache),
        );
        if (mounted) {
          setState(() {
            _profileFuture = Future.value(existingCache);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProfilePublic = previous;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile visibility: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingProfileVisibility = false;
        });
      }
    }
  }

  void _setSidebarOpen(bool open) {
    if (_sidebarOpen == open) return;
    setState(() => _sidebarOpen = open);
    widget.onShellNavVisibilityChanged?.call(open);
  }

  void _openScreen(Widget page) {
    _setSidebarOpen(false);
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  void _openShellTab(MoodiaryTab tab, {bool fromSidebar = false}) {
    _setSidebarOpen(false);
    final onShellTabSelected = widget.onShellTabSelected;
    if (onShellTabSelected != null) {
      onShellTabSelected(tab, fromSidebar: false);
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: MoodiaryShell(
          userName: _currentUserName,
          companionId: _companionId,
          companionName: _companionName,
          initialProfileAvatarUrl: _selectedAvatarDataUrl ?? _currentAvatarUrl,
          initialTab: tab,
          initialHideTopNav: false,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await UserCache.clear(prefs);
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

  String _todayStr() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed =
        notification.metrics.pixels > context.mdHeaderCollapseOffset;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
    return false;
  }

  Widget _buildProfileHeader(BuildContext context) {
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
                      onPressed: () => _setSidebarOpen(true),
                      icon: Icon(Icons.menu, color: primaryText, size: 26),
                      tooltip: 'Open menu',
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _todayStr(),
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _isEditing = !_isEditing),
                      icon: Icon(
                        _isEditing ? Icons.close : Icons.edit,
                        color: primaryText,
                        size: 22,
                      ),
                      tooltip: _isEditing ? 'Stop editing' : 'Edit profile',
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: context.mdHeaderCollapseDuration,
                  curve: Curves.easeOutCubic,
                  child: _headerCollapsed
                      ? const SizedBox.shrink()
                      : AnimatedOpacity(
                          duration: context.mdHeaderFadeDuration,
                          opacity: _headerCollapsed ? 0 : 1,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'User Profile',
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
                                  'Your mood summary, MBTI progress, and account details.',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.showTopNav)
                _buildProfileHeader(context)
              else
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
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
                    final partner =
                        bundle?['profile']?['partner'] as Map<String, dynamic>?;
                    if (userData == null) {
                      return const Center(child: Text('Profile not found'));
                    }

                    final posts =
                        (bundle?['posts'] as List<Map<String, dynamic>>? ??
                                const [])
                            .where(
                              (p) =>
                                  p['isMine'] == true ||
                                  p['authorName'] == userData['name'],
                            )
                            .take(3)
                            .toList();
                    if (!_didHydrateProfileVisibility) {
                      _isProfilePublic =
                          (userData['isProfilePublic'] as bool?) ?? false;
                      _didHydrateProfileVisibility = true;
                    }
                    final mbtiHistory =
                        (bundle?['mbtiHistory']
                                    as List<Map<String, dynamic>>? ??
                                const [])
                            .take(3)
                            .toList();

                    _currentAvatarUrl = userData['avatarUrl'] as String?;
                    final displayedAvatarUrl =
                        _selectedAvatarDataUrl ?? _currentAvatarUrl;
                    final displayedAvatarImage = _cachedAvatarImage(
                      displayedAvatarUrl,
                    );
                    final partnerAvatarImage = _cachedAvatarImage(
                      partner?['avatarUrl'] as String?,
                    );

                    if (!_isEditing &&
                        _nameController.text.isEmpty &&
                        userData['name'] != null) {
                      _nameController.text = userData['name'] as String;
                      _emailController.text =
                          userData['email'] as String? ?? '';
                      _bioController.text = userData['bio'] as String? ?? '';
                    }
                    final isNarrowProfileLayout =
                        MediaQuery.of(context).size.width < 520;
                    final avatarRadius = isNarrowProfileLayout ? 40.0 : 48.0;
                    final avatarIconSize = isNarrowProfileLayout ? 36.0 : 44.0;

                    return Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: _onScrollNotification,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 128),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: GlassContainer(
                                    blurSigma: context.mdGlassBlurMedium,
                                    borderRadius: BorderRadius.circular(16),
                                    backgroundColor: context.mdGlassSurface,
                                    borderColor: context.mdGlassBorder,
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Column(
                                          children: [
                                            Stack(
                                              children: [
                                                CircleAvatar(
                                                  radius: avatarRadius,
                                                  backgroundImage:
                                                      displayedAvatarImage,
                                                  child:
                                                      displayedAvatarImage ==
                                                          null
                                                      ? Icon(
                                                          Icons.person,
                                                          size: avatarIconSize,
                                                        )
                                                      : null,
                                                ),
                                                if (_isEditing)
                                                  Positioned(
                                                    right: -2,
                                                    bottom: -2,
                                                    child: InkWell(
                                                      onTap: _pickAvatarImage,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              6,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color: cs.primary,
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Icon(
                                                          Icons
                                                              .photo_camera_outlined,
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
                                              (userData['name'] as String? ??
                                                      'NAME')
                                                  .toUpperCase(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Name',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(height: 8),
                                              if (_isEditing)
                                                TextField(
                                                  controller: _nameController,
                                                  decoration: InputDecoration(
                                                    hintText: 'Your name',
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Text(
                                                  userData['name'] as String? ??
                                                      'N/A',
                                                ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'Email',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(height: 8),
                                              if (_isEditing)
                                                TextField(
                                                  controller: _emailController,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'your.email@example.com',
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Text(
                                                  userData['email']
                                                          as String? ??
                                                      'N/A',
                                                ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'Bio',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(height: 8),
                                              if (_isEditing)
                                                TextField(
                                                  controller: _bioController,
                                                  maxLines: 4,
                                                  maxLength: 500,
                                                  keyboardType:
                                                      TextInputType.multiline,
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'Tell us about yourself...',
                                                    helperText:
                                                        'You can use emojis in your bio.',
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Text(
                                                  userData['bio'] as String? ??
                                                      'No bio',
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GlassContainer(
                                        blurSigma: context.mdGlassBlurMedium,
                                        borderRadius: BorderRadius.circular(12),
                                        backgroundColor: context.mdGlassSurface,
                                        borderColor: context.mdGlassBorder,
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                                _MoodMini(
                                                  asset: _currentMoodAsset,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    _currentMoodLabel,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
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
                                    SizedBox(
                                      width: 120,
                                      child: GlassContainer(
                                        blurSigma: context.mdGlassBlurMedium,
                                        borderRadius: BorderRadius.circular(12),
                                        backgroundColor: context.mdGlassSurface,
                                        borderColor: context.mdGlassBorder,
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Mood Score',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
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
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: GlassContainer(
                                    blurSigma: context.mdGlassBlurMedium,
                                    borderRadius: BorderRadius.circular(12),
                                    backgroundColor: context.mdGlassSurface,
                                    borderColor: context.mdGlassBorder,
                                    padding: const EdgeInsets.all(12),
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
                                  ),
                                ),
                                if (partner != null) ...[
                                  const SizedBox(height: 10),
                                  Material(
                                    color: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () async {
                                        final partnerId = partner['id']
                                            ?.toString();
                                        if (partnerId == null ||
                                            partnerId.isEmpty) {
                                          return;
                                        }
                                        await showUserProfilePopup(
                                          context,
                                          userId: partnerId,
                                        );
                                      },
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundImage:
                                                  partnerAvatarImage,
                                              child: partnerAvatarImage == null
                                                  ? const Icon(
                                                      Icons.favorite_outline,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Partner',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    (partner['name']
                                                            as String?) ??
                                                        'Partner',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              color: Color(0xFFEC4899),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        (userData['mbtiLatestType']
                                                as String?) ??
                                            'No MBTI result yet',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton(
                                          onPressed: () async {
                                            final completed =
                                                await Navigator.of(
                                                  context,
                                                ).push<bool>(
                                                  FadeSlideRoute(
                                                    page: MbtiTestScreen(
                                                      userName:
                                                          _currentUserName,
                                                    ),
                                                  ),
                                                );
                                            if (completed == true && mounted) {
                                              await _refreshProfileBundleInBackground();
                                            }
                                          },
                                          child: Text(
                                            (userData['mbtiLatestType']
                                                        as String?) ==
                                                    null
                                                ? 'Take MBTI Test'
                                                : 'Retake MBTI Test',
                                          ),
                                        ),
                                      ),
                                      if (mbtiHistory.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          'Recent MBTI results',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        ...mbtiHistory.map((entry) {
                                          final type =
                                              (entry['mbtiType'] as String?) ??
                                              'N/A';
                                          final createdAt =
                                              (entry['createdAt'] as String?) ??
                                              '';
                                          final dateText = createdAt.isEmpty
                                              ? ''
                                              : createdAt.split('T').first;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              dateText.isEmpty
                                                  ? type
                                                  : '$type • $dateText',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_month_outlined,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Calendar Preview',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Today: $_currentMoodLabel',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Mood score: $_todayMoodScore • Streak: $_streakCount ${_streakCount == 1 ? 'day' : 'days'}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _openScreen(
                                                CalendarScreen(
                                                  userName: _currentUserName,
                                                  companionId: _companionId,
                                                  companionName: _companionName,
                                                ),
                                              ),
                                              child: const Text(
                                                'Open Calendar',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _openScreen(
                                                JournalScreen(
                                                  userName: _currentUserName,
                                                  companionId: _companionId,
                                                  companionName: _companionName,
                                                ),
                                              ),
                                              child: const Text('Open Journal'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
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
                                      title:
                                          (p['title'] as String?) ??
                                          'Untitled Post',
                                      subtitle: (p['content'] as String?) ?? '',
                                      leading: Icons.forum_outlined,
                                    ),
                                  ),
                                Text(
                                  'Profile Visibility',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                GlassContainer(
                                  blurSigma: context.mdGlassBlurMedium,
                                  borderRadius: BorderRadius.circular(14),
                                  backgroundColor: context.mdGlassSurface,
                                  borderColor: context.mdGlassBorder,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Public profile'),
                                    subtitle: Text(
                                      _isProfilePublic
                                          ? 'Others can open your profile from forums and friends.'
                                          : 'Only you can open your full profile.',
                                    ),
                                    value: _isProfilePublic,
                                    onChanged: _savingProfileVisibility
                                        ? null
                                        : _updateProfileVisibility,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                GlassContainer(
                                  blurSigma: context.mdGlassBlurMedium,
                                  borderRadius: BorderRadius.circular(14),
                                  backgroundColor: context.mdGlassSurface,
                                  borderColor: context.mdGlassBorder,
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                    userData['createdAt']
                                                        as String,
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
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        if (_isEditing)
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: SafeArea(
                              top: false,
                              child: GlassContainer(
                                blurSigma: context.mdGlassBlurLarge,
                                borderRadius: BorderRadius.circular(18),
                                backgroundColor: context.mdGlassSurfaceStrong,
                                borderColor: context.mdGlassBorder,
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
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            GestureDetector(
              onTap: () => _setSidebarOpen(false),
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
              userName: _currentUserName,
              activeSection: SidebarSection.userProfile,
              onClose: () => _setSidebarOpen(false),
              onNavigateHome: () => _openShellTab(MoodiaryTab.home),
              onNavigateUserProfile: () => _setSidebarOpen(false),
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
              onNavigateFriends: () => _openShellTab(MoodiaryTab.buddies),
              onNavigateForums: () => _openShellTab(MoodiaryTab.forums),
              onNavigateResources: () => _openShellTab(MoodiaryTab.resources),
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: _currentUserName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: _currentUserName)),
              onLogout: () {
                _setSidebarOpen(false);
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
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: BorderRadius.circular(14),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      margin: const EdgeInsets.only(bottom: 8),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
