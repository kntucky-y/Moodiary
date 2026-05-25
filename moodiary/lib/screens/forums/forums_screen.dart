import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/calendar_screen.dart';
import '../journal/journal_screen.dart';
import '../app_shell.dart';
import '../companion/companion_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import '../../utils/transitions.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/local_notifications_service.dart';
import '../../services/auth_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/avatar_utils.dart';
import '../../utils/user_cache.dart';
import '../../widgets/user_profile_popup.dart';
import '../../widgets/glass.dart';

const _kPurple = Color(0xFFA076F9);
const _kSubtle = Color(0xFF8A8A8D);
const _kBaseUrl = kBackendBaseUrl;
const _kForumsCacheKey = 'forums_cache_v1';

const _kCardPalette = <Color>[
  Color(0xFFE8DDF6),
  Color(0xFFF5DEE9),
  Color(0xFFD9F0DF),
  Color(0xFFF8F2C9),
  Color(0xFFDDEBFF),
];

const _commentMoodAssets = <String>[
  'assets/terrible.png',
  'assets/bad.png',
  'assets/okay.png',
  'assets/good.png',
  'assets/excellent.png',
];

class ForumsScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;
  final String? initialPostId;
  final ShellTabSelector? onShellTabSelected;
  final bool showTopNav;
  final ShellNavVisibilitySetter? onShellNavVisibilityChanged;

  const ForumsScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
    this.initialPostId,
    this.onShellTabSelected,
    this.showTopNav = true,
    this.onShellNavVisibilityChanged,
  });

  @override
  State<ForumsScreen> createState() => _ForumsScreenState();
}

class _ForumsScreenState extends State<ForumsScreen> {
  bool _loading = true;
  bool _sidebarOpen = false;
  bool _fabExpanded = false;
  bool _showMineOnly = false;
  bool _headerCollapsed = false;
  bool _showArchived = false;

  String? _token;
  String? _activePostId;
  List<_ForumPost> _posts = [];
  final Set<String> _likeBusyPostIds = <String>{};
  final Set<String> _workingPostIds = <String>{};
  final Set<String> _loadingDetailPostIds = <String>{};
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (!mounted) return;
    setState(() => _token = token);
    if (token == null) {
      setState(() => _loading = false);
    } else {
      await _loadCachedPosts();
      await _fetchPosts();
    }
  }

  Future<void> _loadCachedPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCache = prefs.getString(_kForumsCacheKey);
    if (rawCache == null || rawCache.isEmpty || !mounted) return;
    try {
      final decoded = jsonDecode(rawCache) as Map<String, dynamic>;
      final posts = (decoded['posts'] as List<dynamic>? ?? const [])
          .map((e) => _ForumPost.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _posts = posts;
        _activePostId = decoded['activePostId'] as String?;
        _showMineOnly = (decoded['showMineOnly'] as bool?) ?? false;
        _showArchived = (decoded['showArchived'] as bool?) ?? false;
        _loading = posts.isEmpty;
      });
    } catch (_) {
      // Ignore malformed cache and continue with a network fetch.
    }
  }

  Future<void> _savePostsCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = {
      'posts': _posts
          .map(
            (post) => {
              'id': post.id,
              'title': post.title,
              'content': post.content,
              'isAnonymous': post.isAnonymous,
              'authorId': post.authorId,
              'author': post.author,
              'authorAvatarUrl': post.authorAvatarUrl,
              'companionId': post.companionId,
              'likes': post.likes,
              'likedByMe': post.likedByMe,
              'isMine': post.isMine,
              'commentCount': post.commentCount,
              'comments': post.comments
                  .map(
                    (comment) => {
                      'id': comment.id,
                      'moodAsset': comment.moodAsset,
                      'text': comment.text,
                      'isAnonymous': comment.isAnonymous,
                      'authorName': comment.authorName,
                      'authorAvatarUrl': comment.authorAvatarUrl,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'activePostId': _activePostId,
      'showMineOnly': _showMineOnly,
      'showArchived': _showArchived,
    };
    await prefs.setString(_kForumsCacheKey, jsonEncode(cache));
  }

  Map<String, String> get _authHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  List<_ForumPost> get _visiblePosts =>
      _showMineOnly ? _posts.where((p) => p.isMine).toList() : _posts;

  Future<void> _fetchPosts({bool silent = true}) async {
    if (_token == null) {
      if (_loading) setState(() => _loading = false);
      return;
    }
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      http.Response resp;
      try {
        resp = await http
            .get(
              Uri.parse('$_kBaseUrl/api/forums?archived=$_showArchived'),
              headers: _authHeaders,
            )
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        resp = await http
            .get(
              Uri.parse('$_kBaseUrl/api/forums?archived=$_showArchived'),
              headers: _authHeaders,
            )
            .timeout(const Duration(seconds: 45));
      }
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        final parsed = data
            .map((e) => _ForumPost.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _posts = parsed;
          if (widget.initialPostId != null &&
              _posts.any((p) => p.id == widget.initialPostId)) {
            _activePostId = widget.initialPostId;
          }
          if (_activePostId != null &&
              !_posts.any((p) => p.id == _activePostId)) {
            _activePostId = null;
          }
          _loading = false;
        });
        await _savePostsCache();
      } else {
        setState(() => _loading = false);
        if (!silent || _posts.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load forums. Please try again.'),
            ),
          );
        }
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent || _posts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forums timed out. Please try again.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent || _posts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load forums. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _fetchPostDetail(String postId) async {
    if (_token == null || _loadingDetailPostIds.contains(postId)) return;
    setState(() => _loadingDetailPostIds.add(postId));
    try {
      final resp = await http
          .get(
            Uri.parse('$_kBaseUrl/api/forums/$postId'),
            headers: _authHeaders,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final updated = _ForumPost.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
        final index = _posts.indexWhere((p) => p.id == postId);
        if (index >= 0) {
          setState(() {
            _posts[index] = updated;
          });
          await _savePostsCache();
        }
      }
    } catch (_) {
      // Keep the lightweight post card if detail loading fails.
    } finally {
      if (mounted) {
        setState(() => _loadingDetailPostIds.remove(postId));
      }
    }
  }

  void _setSidebarOpen(bool open) {
    if (_sidebarOpen == open) return;
    setState(() {
      _sidebarOpen = open;
      if (open) _fabExpanded = false;
    });
    widget.onShellNavVisibilityChanged?.call(open);
  }

  void _openSidebar() => _setSidebarOpen(true);

  void _closeSidebar() => _setSidebarOpen(false);

  void _openScreen(Widget page) {
    _closeSidebar();
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  void _openShellTab(MoodiaryTab tab, {bool fromSidebar = false}) {
    _closeSidebar();
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

  Future<void> _logout() async {
    _closeSidebar();
    final prefs = await SharedPreferences.getInstance();
    await UserCache.clear(prefs);
    await prefs.remove('token');
    await prefs.remove('user_name');
    await prefs.remove('user_id');
    await prefs.remove('companion_id');
    await prefs.remove('companion_name');
    RealtimeNotifications.instance.disconnect();
    await ThemeController.instance.resetToDefault();
    await LocalNotificationsService.instance.cancelAllScheduled();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(page: const OnboardingScreen()),
      (_) => false,
    );
  }

  Future<void> _createPost({
    required String title,
    required String content,
    required bool anonymous,
  }) async {
    if (_token == null) return;
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'title': title,
          'content': content,
          'isAnonymous': anonymous,
          'companionId': widget.companionId,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 201) {
        final created = _ForumPost.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
        setState(() {
          if (!_showArchived) {
            _posts.insert(0, created);
          }
          _fabExpanded = false;
        });
        await _savePostsCache();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your post has been published.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish post: ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to publish post: $e')));
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmText,
    Color confirmColor = _kPurple,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _toggleArchived() async {
    setState(() {
      _showArchived = !_showArchived;
      _showMineOnly = false;
      _activePostId = null;
      _fabExpanded = false;
    });
    await _fetchPosts(silent: false);
  }

  Future<void> _archivePost(String postId) async {
    if (_token == null) return;
    final shouldArchive = await _confirmAction(
      title: 'Archive post?',
      message: 'This will move it to Archive and you can recover it later.',
      confirmText: 'Archive',
    );
    if (!shouldArchive) return;

    final removedIndex = _posts.indexWhere((p) => p.id == postId);
    final removedPost = removedIndex >= 0 ? _posts[removedIndex] : null;
    setState(() => _workingPostIds.add(postId));
    try {
      if (removedIndex >= 0) {
        setState(() {
          _posts.removeAt(removedIndex);
          if (_activePostId == postId) _activePostId = null;
        });
        await _savePostsCache();
      }
      final resp = await http.delete(
        Uri.parse('$_kBaseUrl/api/forums/$postId'),
        headers: _authHeaders,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post archived.')));
      } else {
        if (removedPost != null && removedIndex >= 0) {
          setState(() {
            _posts.insert(removedIndex, removedPost);
          });
          await _savePostsCache();
          if (!mounted) return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to archive post: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        if (removedPost != null && removedIndex >= 0) {
          setState(() {
            _posts.insert(removedIndex, removedPost);
          });
          await _savePostsCache();
          if (!mounted) return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Archive failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _workingPostIds.remove(postId));
      }
    }
  }

  Future<void> _recoverPost(String postId) async {
    if (_token == null) return;
    setState(() => _workingPostIds.add(postId));
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums/$postId/recover'),
        headers: _authHeaders,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() {
          _posts.removeWhere((p) => p.id == postId);
          if (_activePostId == postId) _activePostId = null;
        });
        await _savePostsCache();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Post restored.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore post: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _workingPostIds.remove(postId));
      }
    }
  }

  Future<void> _deletePostPermanently(String postId) async {
    if (_token == null) return;
    final shouldDelete = await _confirmAction(
      title: 'Delete permanently?',
      message:
          'This permanently deletes the archived post and cannot be undone.',
      confirmText: 'Delete',
      confirmColor: Colors.red,
    );
    if (!shouldDelete) return;

    final removedIndex = _posts.indexWhere((p) => p.id == postId);
    final removedPost = removedIndex >= 0 ? _posts[removedIndex] : null;
    setState(() => _workingPostIds.add(postId));
    try {
      if (removedIndex >= 0) {
        setState(() {
          _posts.removeAt(removedIndex);
          if (_activePostId == postId) _activePostId = null;
        });
        await _savePostsCache();
      }
      final resp = await http.delete(
        Uri.parse('$_kBaseUrl/api/forums/$postId/permanent'),
        headers: _authHeaders,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post permanently deleted.')),
        );
      } else {
        if (removedPost != null && removedIndex >= 0) {
          setState(() {
            _posts.insert(removedIndex, removedPost);
          });
          await _savePostsCache();
          if (!mounted) return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete post: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        if (removedPost != null && removedIndex >= 0) {
          setState(() {
            _posts.insert(removedIndex, removedPost);
          });
          await _savePostsCache();
          if (!mounted) return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _workingPostIds.remove(postId));
      }
    }
  }

  Future<void> _toggleLike(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0 || _token == null) return;
    final post = _posts[idx];
    if (_likeBusyPostIds.contains(post.id)) return;
    final previousLikes = post.likes;
    final previousLikedByMe = post.likedByMe;
    final optimisticLikes = previousLikedByMe
        ? (previousLikes - 1).clamp(0, 1 << 31).toInt()
        : previousLikes + 1;

    setState(() {
      _likeBusyPostIds.add(post.id);
      post.likedByMe = !previousLikedByMe;
      post.likes = optimisticLikes;
    });
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums/${post.id}/like'),
        headers: _authHeaders,
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() {
          post.likes = (data['likes'] as int?) ?? post.likes;
          post.likedByMe = (data['likedByMe'] as bool?) ?? post.likedByMe;
        });
        await _savePostsCache();
        if (!mounted) return;
      } else {
        setState(() {
          post.likes = previousLikes;
          post.likedByMe = previousLikedByMe;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update like: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          post.likes = previousLikes;
          post.likedByMe = previousLikedByMe;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update like: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _likeBusyPostIds.remove(post.id));
      }
    }
  }

  void _openPostDetail(String postId) {
    setState(() {
      _activePostId = postId;
      _fabExpanded = false;
    });
    unawaited(_fetchPostDetail(postId));
  }

  void _closePostDetail() {
    setState(() => _activePostId = null);
  }

  Future<void> _showComposerDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool anonymous = true;

    final draft = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final primaryText = Theme.of(ctx).colorScheme.onSurface;
        final secondaryText = primaryText.withValues(alpha: 0.7);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Create a post',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryText,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _kSubtle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: titleController,
                      maxLength: 70,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryText,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'Title...',
                        hintStyle: TextStyle(color: secondaryText),
                      ),
                    ),
                    TextField(
                      controller: contentController,
                      maxLines: 5,
                      maxLength: 300,
                      style: TextStyle(color: primaryText),
                      decoration: InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'Start typing...',
                        hintStyle: TextStyle(color: secondaryText),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          'Post anonymously',
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Switch.adaptive(
                          value: anonymous,
                          activeTrackColor: _kPurple,
                          onChanged: (v) => setDialogState(() => anonymous = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final title = titleController.text.trim();
                              final content = contentController.text.trim();
                              if (title.isEmpty || content.isEmpty) return;
                              Navigator.of(ctx).pop({
                                'title': title,
                                'content': content,
                                'anonymous': anonymous,
                              });
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: _kPurple,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('Post'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (draft == null) return;
    await _createPost(
      title: draft['title'] as String,
      content: draft['content'] as String,
      anonymous: draft['anonymous'] as bool,
    );
  }

  Future<void> _showReportDialog(String postId) async {
    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex < 0 || _token == null) return;
    final reasonCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final primaryText = Theme.of(ctx).colorScheme.onSurface;
        final secondaryText = primaryText.withValues(alpha: 0.7);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Report Post',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: primaryText,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(Icons.close_rounded, color: secondaryText),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  style: TextStyle(color: primaryText),
                  decoration: InputDecoration(
                    hintText: 'Reason for reporting...',
                    hintStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 3,
                  style: TextStyle(color: primaryText),
                  decoration: InputDecoration(
                    hintText: 'Additional details...',
                    hintStyle: TextStyle(color: secondaryText),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final reason = reasonCtrl.text.trim();
                      if (reason.isEmpty) return;
                      Navigator.of(ctx).pop({
                        'reason': reason,
                        'details': detailsCtrl.text.trim(),
                      });
                    },
                    style: FilledButton.styleFrom(backgroundColor: _kPurple),
                    child: const Text('Submit Report'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (payload == null) return;

    try {
      final post = _posts[postIndex];
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums/${post.id}/report'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thanks. "${post.title}" was flagged for review.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit report: ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit report: $e')));
    }
  }

  Future<void> _addComment(String text) async {
    final activeId = _activePostId;
    if (activeId == null || _token == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final i = _posts.indexWhere((p) => p.id == activeId);
    if (i < 0) return;
    final post = _posts[i];

    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums/${post.id}/comments'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'text': trimmed,
          'moodAsset':
              _commentMoodAssets[_random.nextInt(_commentMoodAssets.length)],
          'isAnonymous': true,
        }),
      );
      if (!mounted) return;
      if (resp.statusCode == 201) {
        final updated = _ForumPost.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>,
        );
        setState(() {
          final idx = _posts.indexWhere((p) => p.id == updated.id);
          if (idx >= 0) {
            _posts[idx] = updated;
            _activePostId = updated.id;
          }
        });
        await _savePostsCache();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add comment: ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add comment: $e')));
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year/$month/$day';
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final collapsed =
        notification.metrics.pixels > context.mdHeaderCollapseOffset;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    final visiblePosts = _visiblePosts;
    _ForumPost? activePost;
    if (_activePostId != null) {
      for (final post in _posts) {
        if (post.id == _activePostId) {
          activePost = post;
          break;
        }
      }
    }
    final detailPost = activePost;
    final detailLoading =
        detailPost != null && _loadingDetailPostIds.contains(detailPost.id);

    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          Column(
            children: [
              if (widget.showTopNav)
                SafeArea(
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
                                  onPressed: _openSidebar,
                                  icon: Icon(
                                    Icons.menu,
                                    color: primaryText,
                                    size: 26,
                                  ),
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
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: _toggleArchived,
                                      icon: Icon(
                                        _showArchived
                                            ? Icons.unarchive_outlined
                                            : Icons.archive_outlined,
                                        color: _showArchived
                                            ? _kPurple
                                            : primaryText,
                                        size: 22,
                                      ),
                                      tooltip: _showArchived
                                          ? 'Show active posts'
                                          : 'Show archived posts',
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          _fetchPosts(silent: false),
                                      icon: Icon(
                                        Icons.refresh_rounded,
                                        color: primaryText,
                                        size: 22,
                                      ),
                                      tooltip: 'Refresh forums',
                                    ),
                                  ],
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
                                              'Forums',
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
                                              _showArchived
                                                  ? 'Archived forum posts'
                                                  : 'A safe space to share and connect',
                                              style: TextStyle(
                                                color: secondaryText,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (!_showArchived && _showMineOnly)
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                onPressed: () => setState(
                                                  () => _showMineOnly = false,
                                                ),
                                                icon: const Icon(
                                                  Icons.filter_alt_off,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Showing only my posts',
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
                )
              else
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _token == null
                      ? const _ForumEmptyState(
                          title: 'Please login first',
                          subtitle: 'Forums requires an authenticated account.',
                          icon: Icons.lock_outline_rounded,
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: detailPost != null
                              ? _ForumDetailView(
                                  key: const ValueKey('forum-detail'),
                                  post: detailPost,
                                  showArchivedActions: _showArchived,
                                  onOpenPost: _openPostDetail,
                                  onClose: _closePostDetail,
                                  onLikeTap: () => _toggleLike(detailPost.id),
                                  onReportTap: () =>
                                      _showReportDialog(detailPost.id),
                                  onArchiveTap: detailPost.isMine
                                      ? () => _archivePost(detailPost.id)
                                      : null,
                                  onRecoverTap: detailPost.isMine
                                      ? () => _recoverPost(detailPost.id)
                                      : null,
                                  onDeletePermanentlyTap: detailPost.isMine
                                      ? () => _deletePostPermanently(
                                          detailPost.id,
                                        )
                                      : null,
                                  onAddComment: _addComment,
                                  loadingComments: detailLoading,
                                )
                              : _ForumListView(
                                  key: const ValueKey('forum-list'),
                                  posts: visiblePosts,
                                  companionId: widget.companionId,
                                  fabExpanded: _fabExpanded,
                                  showArchivedActions: _showArchived,
                                  onOpenPost: _openPostDetail,
                                  onPostTap: (i) =>
                                      _openPostDetail(visiblePosts[i].id),
                                  onLikeTap: (i) =>
                                      _toggleLike(visiblePosts[i].id),
                                  onReportTap: (i) =>
                                      _showReportDialog(visiblePosts[i].id),
                                  onArchiveTap: (i) =>
                                      _archivePost(visiblePosts[i].id),
                                  onRecoverTap: (i) =>
                                      _recoverPost(visiblePosts[i].id),
                                  onDeletePermanentlyTap: (i) =>
                                      _deletePostPermanently(
                                        visiblePosts[i].id,
                                      ),
                                  onExpandFab: () =>
                                      setState(() => _fabExpanded = true),
                                  onCollapseFab: () =>
                                      setState(() => _fabExpanded = false),
                                  onCreatePost: _showArchived
                                      ? null
                                      : _showComposerDialog,
                                ),
                        ),
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            GestureDetector(
              onTap: _closeSidebar,
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
              activeSection: SidebarSection.forums,
              onClose: _closeSidebar,
              onNavigateHome: () => _openShellTab(MoodiaryTab.home),
              onNavigateUserProfile: () => _openShellTab(MoodiaryTab.profile),
              onNavigateCalendar: () => _openScreen(
                CalendarScreen(
                  userName: widget.userName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateJournal: () => _openScreen(
                JournalScreen(
                  userName: widget.userName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateFriends: () => _openShellTab(MoodiaryTab.buddies),
              onNavigateForums: _closeSidebar,
              onNavigateResources: () => _openShellTab(MoodiaryTab.resources),
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: widget.userName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: widget.userName)),
              onLogout: () {
                _closeSidebar();
                _logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumListView extends StatelessWidget {
  final List<_ForumPost> posts;
  final int companionId;
  final bool fabExpanded;
  final bool showArchivedActions;
  final ValueChanged<String> onOpenPost;
  final ValueChanged<int> onPostTap;
  final ValueChanged<int> onLikeTap;
  final ValueChanged<int> onReportTap;
  final ValueChanged<int> onArchiveTap;
  final ValueChanged<int> onRecoverTap;
  final ValueChanged<int> onDeletePermanentlyTap;
  final VoidCallback onExpandFab;
  final VoidCallback onCollapseFab;
  final VoidCallback? onCreatePost;

  const _ForumListView({
    super.key,
    required this.posts,
    required this.companionId,
    required this.fabExpanded,
    required this.showArchivedActions,
    required this.onOpenPost,
    required this.onPostTap,
    required this.onLikeTap,
    required this.onReportTap,
    required this.onArchiveTap,
    required this.onRecoverTap,
    required this.onDeletePermanentlyTap,
    required this.onExpandFab,
    required this.onCollapseFab,
    required this.onCreatePost,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return Stack(
      children: [
        GlassContainer(
          blurSigma: context.mdGlassBlurMedium,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          backgroundColor: context.mdGlassSurface,
          borderColor: context.mdGlassBorder,
          padding: EdgeInsets.zero,
          child: posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 62,
                        color: secondaryText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No posts yet',
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap + to share the first supportive post.',
                        style: TextStyle(color: secondaryText, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    MediaQuery.of(context).padding.bottom + 140,
                  ),
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) {
                    return _PostCard(
                      post: posts[i],
                      showArchivedActions: showArchivedActions,
                      onTap: () => onPostTap(i),
                      onLikeTap: () => onLikeTap(i),
                      onReportTap: () => onReportTap(i),
                      onArchiveTap: () => onArchiveTap(i),
                      onRecoverTap: () => onRecoverTap(i),
                      onDeletePermanentlyTap: () => onDeletePermanentlyTap(i),
                      onAuthorTap: () {
                        final authorId = posts[i].authorId;
                        if (authorId == null || authorId.isEmpty) return;
                        () async {
                          final selectedPostId = await showUserProfilePopup(
                            context,
                            userId: authorId,
                          );
                          if (selectedPostId != null) {
                            onOpenPost(selectedPostId);
                          }
                        }();
                      },
                    );
                  },
                ),
        ),
        if (onCreatePost != null)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 80,
            right: 16,
            child: SizedBox(
              width: 54,
              height: 54,
              child: GlassContainer(
                blurSigma: context.mdGlassBlurMedium,
                borderRadius: BorderRadius.circular(27),
                backgroundColor: _kPurple.withValues(alpha: 0.58),
                borderColor: context.mdGlassBorder,
                padding: EdgeInsets.zero,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(27),
                    onTap: onCreatePost,
                    child: const Center(
                      child: Icon(Icons.add, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ForumDetailView extends StatefulWidget {
  final _ForumPost post;
  final bool showArchivedActions;
  final bool loadingComments;
  final ValueChanged<String> onOpenPost;
  final VoidCallback onClose;
  final VoidCallback onLikeTap;
  final VoidCallback onReportTap;
  final VoidCallback? onArchiveTap;
  final VoidCallback? onRecoverTap;
  final VoidCallback? onDeletePermanentlyTap;
  final Future<void> Function(String) onAddComment;

  const _ForumDetailView({
    super.key,
    required this.post,
    required this.showArchivedActions,
    required this.loadingComments,
    required this.onOpenPost,
    required this.onClose,
    required this.onLikeTap,
    required this.onReportTap,
    this.onArchiveTap,
    this.onRecoverTap,
    this.onDeletePermanentlyTap,
    required this.onAddComment,
  });

  @override
  State<_ForumDetailView> createState() => _ForumDetailViewState();
}

class _ForumDetailViewState extends State<_ForumDetailView> {
  final TextEditingController _commentCtrl = TextEditingController();
  bool _submittingComment = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    final post = widget.post;
    return Container(
      color: context.mdScaffold,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PostCard(
                        post: post,
                        compactText: false,
                        showArchivedActions: widget.showArchivedActions,
                        onTap: () {},
                        onLikeTap: widget.onLikeTap,
                        onReportTap: widget.onReportTap,
                        onArchiveTap: widget.onArchiveTap,
                        onRecoverTap: widget.onRecoverTap,
                        onDeletePermanentlyTap: widget.onDeletePermanentlyTap,
                        onAuthorTap: () {
                          final authorId = post.authorId;
                          if (authorId == null || authorId.isEmpty) return;
                          () async {
                            final selectedPostId = await showUserProfilePopup(
                              context,
                              userId: authorId,
                            );
                            if (selectedPostId != null) {
                              widget.onOpenPost(selectedPostId);
                            }
                          }();
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, color: _kSubtle),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (widget.loadingComments)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ...post.comments.map(
                  (c) => GlassContainer(
                    blurSigma: context.mdGlassBlurSmall,
                    borderRadius: BorderRadius.circular(14),
                    backgroundColor: context.mdGlassSurface,
                    borderColor: context.mdGlassBorder,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: avatarImageProvider(
                            c.authorAvatarUrl,
                          ),
                          child: avatarImageProvider(c.authorAvatarUrl) == null
                              ? Image.asset(
                                  c.moodAsset,
                                  width: 24,
                                  height: 24,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                        Icons.sentiment_satisfied_alt_rounded,
                                        color: _kSubtle,
                                      ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.text,
                            style: TextStyle(
                              color: primaryText,
                              fontSize: 17,
                              height: 1.35,
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
          SafeArea(
            top: false,
            child: GlassContainer(
              blurSigma: context.mdGlassBlurSmall,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              backgroundColor: context.mdGlassSurfaceStrong,
              borderColor: context.mdGlassBorder,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      enabled: !_submittingComment,
                      decoration: InputDecoration(
                        hintText: 'Add a supportive comment',
                        hintStyle: TextStyle(color: secondaryText),
                        filled: true,
                        fillColor: context.mdInputFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: GlassContainer(
                      blurSigma: context.mdGlassBlurSmall,
                      borderRadius: BorderRadius.circular(23),
                      backgroundColor: _kPurple.withValues(alpha: 0.58),
                      borderColor: context.mdGlassBorder,
                      padding: EdgeInsets.zero,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(23),
                          onTap: _submittingComment
                              ? null
                              : () async {
                                  final text = _commentCtrl.text;
                                  if (text.trim().isEmpty) return;
                                  setState(() => _submittingComment = true);
                                  await widget.onAddComment(text);
                                  if (!mounted) return;
                                  _commentCtrl.clear();
                                  setState(() => _submittingComment = false);
                                },
                          child: Center(
                            child: _submittingComment
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final _ForumPost post;
  final bool compactText;
  final bool showArchivedActions;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final VoidCallback onReportTap;
  final VoidCallback? onArchiveTap;
  final VoidCallback? onRecoverTap;
  final VoidCallback? onDeletePermanentlyTap;
  final VoidCallback? onAuthorTap;

  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onLikeTap,
    required this.onReportTap,
    this.showArchivedActions = false,
    this.onArchiveTap,
    this.onRecoverTap,
    this.onDeletePermanentlyTap,
    this.onAuthorTap,
    this.compactText = true,
  });

  @override
  Widget build(BuildContext context) {
    final cardSurface = post.cardColor.withValues(
      alpha: context.isDarkMode ? 0.72 : 0.92,
    );
    final cardBrightness = ThemeData.estimateBrightnessForColor(cardSurface);
    final onCardText = cardBrightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.96)
        : const Color(0xFF1F2937);
    final onCardSubtle = cardBrightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.74)
        : const Color(0xFF6B7280);
    final likeColor = post.likedByMe
        ? Colors.red
        : (cardBrightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.75)
              : _kSubtle);
    return TapScale(
      onTap: onTap,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurSmall,
        borderRadius: BorderRadius.circular(18),
        backgroundColor: cardSurface,
        borderColor: context.mdGlassBorder,
        showTintOverlay: false,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: post.isAnonymous ? null : onAuthorTap,
              child: post.isAnonymous
                  ? Image.asset(
                      post.doodleAsset,
                      width: compactText ? 62 : 74,
                      height: compactText ? 62 : 74,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.face_outlined,
                        size: 56,
                        color: _kSubtle,
                      ),
                    )
                  : CircleAvatar(
                      radius: compactText ? 31 : 37,
                      backgroundImage: avatarImageProvider(
                        post.authorAvatarUrl,
                      ),
                      child: avatarImageProvider(post.authorAvatarUrl) == null
                          ? const Icon(Icons.person_outline, color: _kSubtle)
                          : null,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: compactText ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onCardText,
                      fontSize: compactText ? 15.5 : 18,
                      height: compactText ? 1.15 : 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: compactText ? 4 : 6),
                  if (!compactText && !post.isAnonymous)
                    GestureDetector(
                      onTap: onAuthorTap,
                      child: Text(
                        'Posted by ${post.author}',
                        style: TextStyle(
                          color: onCardSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (!compactText && !post.isAnonymous)
                    const SizedBox(height: 4),
                  Text(
                    post.content,
                    maxLines: compactText ? 3 : null,
                    overflow: compactText ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      color: onCardText,
                      fontSize: compactText ? 11.5 : 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.mode_comment_outlined,
                        color: onCardSubtle,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentCount}',
                        style: TextStyle(
                          color: onCardSubtle,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      TapScale(
                        onTap: onLikeTap,
                        scale: 0.9,
                        child: Row(
                          children: [
                            Icon(
                              post.likedByMe
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: likeColor,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.likes}',
                              style: TextStyle(
                                color: likeColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (showArchivedActions && post.isMine) ...[
                        GestureDetector(
                          onTap: onRecoverTap,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.restore_rounded,
                            color: onCardText,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: onDeletePermanentlyTap,
                          behavior: HitTestBehavior.opaque,
                          child: const Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                      ] else if (post.isMine) ...[
                        GestureDetector(
                          onTap: onArchiveTap,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.archive_outlined,
                            color: onCardText,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: onReportTap,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: onCardText,
                            size: 20,
                          ),
                        ),
                      ] else
                        GestureDetector(
                          onTap: onReportTap,
                          behavior: HitTestBehavior.opaque,
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: onCardText,
                            size: 20,
                          ),
                        ),
                    ],
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

class _ForumEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ForumEmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return GlassContainer(
      blurSigma: context.mdGlassBlurMedium,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      backgroundColor: context.mdGlassSurface,
      borderColor: context.mdGlassBorder,
      padding: EdgeInsets.zero,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 62, color: secondaryText),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: primaryText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: secondaryText, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForumPost {
  final String id;
  final String title;
  final String content;
  final bool isAnonymous;
  final String? authorId;
  final String author;
  final String? authorAvatarUrl;
  final int companionId;
  final bool isMine;
  final List<_ForumComment> comments;
  final int commentCount;
  int likes;
  bool likedByMe;

  _ForumPost({
    required this.id,
    required this.title,
    required this.content,
    required this.isAnonymous,
    this.authorId,
    required this.author,
    this.authorAvatarUrl,
    required this.companionId,
    required this.isMine,
    required this.comments,
    required this.commentCount,
    required this.likes,
    required this.likedByMe,
  });

  factory _ForumPost.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'] as List<dynamic>? ?? [];
    return _ForumPost(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      isAnonymous: (json['isAnonymous'] as bool?) ?? true,
      authorId: json['authorId'] as String?,
      author: json['authorName'] as String? ?? 'Anonymous',
      authorAvatarUrl: json['authorAvatarUrl'] as String?,
      companionId: (json['companionId'] as int?) ?? 1,
      isMine: (json['isMine'] as bool?) ?? false,
      comments: rawComments
          .map((e) => _ForumComment.fromJson(e as Map<String, dynamic>))
          .toList(),
      commentCount:
          (json['commentCount'] as int?) ??
          (json['comments'] as List<dynamic>? ?? const []).length,
      likes: (json['likes'] as int?) ?? 0,
      likedByMe: (json['likedByMe'] as bool?) ?? false,
    );
  }

  Color get cardColor {
    final idx = id.hashCode.abs() % _kCardPalette.length;
    return _kCardPalette[idx];
  }

  String get doodleAsset => 'assets/doodle$companionId.png';
}

class _ForumComment {
  final String id;
  final String moodAsset;
  final String text;
  final bool isAnonymous;
  final String authorName;
  final String? authorAvatarUrl;

  const _ForumComment({
    required this.id,
    required this.moodAsset,
    required this.text,
    required this.isAnonymous,
    required this.authorName,
    this.authorAvatarUrl,
  });

  factory _ForumComment.fromJson(Map<String, dynamic> json) => _ForumComment(
    id: json['id'] as String? ?? '',
    moodAsset: json['moodAsset'] as String? ?? 'assets/okay.png',
    text: json['text'] as String? ?? '',
    isAnonymous: (json['isAnonymous'] as bool?) ?? true,
    authorName: json['authorName'] as String? ?? 'Anonymous',
    authorAvatarUrl: json['authorAvatarUrl'] as String?,
  );
}
