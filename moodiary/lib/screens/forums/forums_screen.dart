import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../journal/journal_screen.dart';
import '../../utils/transitions.dart';

const _kPurple = Color(0xFFA076F9);
const _kDark = Color(0xFF3D3B40);
const _kSubtle = Color(0xFF8A8A8D);
const _kHeaderBg = Color(0xFFF3E8FF);
const _kBaseUrl = 'https://moodiary-production.up.railway.app';

const _kCardPalette = <Color>[
  Color(0xFFE8DDF6),
  Color(0xFFF5DEE9),
  Color(0xFFD9F0DF),
  Color(0xFFF8F2C9),
  Color(0xFFDDEBFF),
];

class _ForumComment {
  final String id;
  final String moodAsset;
  final String text;
  final String authorName;

  const _ForumComment({
    required this.id,
    required this.moodAsset,
    required this.text,
    required this.authorName,
  });

  factory _ForumComment.fromJson(Map<String, dynamic> j) {
    return _ForumComment(
      id: (j['id'] ?? '').toString(),
      moodAsset: (j['moodAsset'] ?? 'assets/okay.png').toString(),
      text: (j['text'] ?? '').toString(),
      authorName: (j['authorName'] ?? 'Anonymous').toString(),
    );
  }
}

class _ForumPost {
  final String id;
  final int companionId;
  final String title;
  final String content;
  final bool anonymous;
  final String author;
  final bool isMine;
  int likes;
  bool likedByMe;
  final List<_ForumComment> comments;

  _ForumPost({
    required this.id,
    required this.companionId,
    required this.title,
    required this.content,
    required this.anonymous,
    required this.author,
    required this.isMine,
    required this.likes,
    required this.likedByMe,
    required this.comments,
  });

  factory _ForumPost.fromJson(Map<String, dynamic> j) {
    final commentsJson = (j['comments'] as List<dynamic>? ?? []);
    return _ForumPost(
      id: (j['id'] ?? '').toString(),
      companionId: (j['companionId'] as int?) ?? 1,
      title: (j['title'] ?? '').toString(),
      content: (j['content'] ?? '').toString(),
      anonymous: (j['isAnonymous'] as bool?) ?? true,
      author: (j['authorName'] ?? 'Anonymous').toString(),
      isMine: (j['isMine'] as bool?) ?? false,
      likes: (j['likes'] as int?) ?? 0,
      likedByMe: (j['likedByMe'] as bool?) ?? false,
      comments: commentsJson
          .map((c) => _ForumComment.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  int get commentCount => comments.length;
  String get doodleAsset => 'assets/doodle$companionId.png';
  Color get cardColor {
    final seed = id.isEmpty ? title : id;
    final idx = seed.hashCode.abs() % _kCardPalette.length;
    return _kCardPalette[idx];
  }
}

class ForumsScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;

  const ForumsScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<ForumsScreen> createState() => _ForumsScreenState();
}

class _ForumsScreenState extends State<ForumsScreen> {
  final List<String> _commentMoodAssets = const [
    'assets/okay.png',
    'assets/good.png',
    'assets/wink.png',
    'assets/bliss.png',
  ];

  List<_ForumPost> _posts = [];
  bool _loading = true;
  bool _fabExpanded = false;
  bool _showMineOnly = false;
  String? _activePostId;
  String? _token;
  final Set<String> _likeBusyPostIds = <String>{};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    await _fetchPosts();
  }

  Map<String, String> get _authHeaders {
    final t = _token;
    if (t == null || t.isEmpty) return {};
    return {'Authorization': 'Bearer $t'};
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  List<_ForumPost> get _visiblePosts =>
      _showMineOnly ? _posts.where((p) => p.isMine).toList() : _posts;

  Future<void> _fetchPosts({bool silent = false}) async {
    if (_token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);

    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/api/forums'),
        headers: _authHeaders,
      );

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        final parsed = data
            .map((e) => _ForumPost.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() {
          _posts = parsed;
          if (_activePostId != null &&
              !_posts.any((p) => p.id == _activePostId)) {
            _activePostId = null;
          }
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load forums: ${resp.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load forums: $e')));
    }
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
          _posts.insert(0, created);
          _fabExpanded = false;
        });
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

  Future<void> _toggleLike(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final post = _posts[idx];
    if (_likeBusyPostIds.contains(post.id)) return;
    if (_token == null) return;

    setState(() => _likeBusyPostIds.add(post.id));
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update like: ${resp.body}')),
        );
      }
    } catch (e) {
      if (mounted) {
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
                        Image.asset(
                          'assets/doodle${widget.companionId}.png',
                          width: 42,
                          height: 42,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.chat_bubble_outline,
                            size: 30,
                            color: _kSubtle,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _kSubtle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    TextField(
                      controller: titleController,
                      maxLength: 70,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: _kDark,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'Title...',
                      ),
                    ),
                    TextField(
                      controller: contentController,
                      maxLines: 5,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        hintText: 'Start typing...',
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          'Post anonymously',
                          style: TextStyle(
                            color: _kDark,
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
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Report Post',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _kDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, color: _kSubtle),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Reason for reporting...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: detailsCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Additional details...',
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
      ),
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
    final random = Random();

    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/forums/${post.id}/comments'),
        headers: {'Content-Type': 'application/json', ..._authHeaders},
        body: jsonEncode({
          'text': trimmed,
          'moodAsset':
              _commentMoodAssets[random.nextInt(_commentMoodAssets.length)],
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

  @override
  Widget build(BuildContext context) {
    final activePostIdx = _activePostId == null
        ? -1
        : _posts.indexWhere((p) => p.id == _activePostId);
    final activePost = activePostIdx >= 0 ? _posts[activePostIdx] : null;
    final visiblePosts = _visiblePosts;

    return Scaffold(
      backgroundColor: _kHeaderBg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            Navigator.of(context).pushAndRemoveUntil(
                              FadeSlideRoute(
                                page: HomeScreen(
                                  userName: widget.userName,
                                  companionId: widget.companionId,
                                  companionName: widget.companionName,
                                ),
                              ),
                              (_) => false,
                            ),
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: _kDark,
                          size: 22,
                        ),
                        tooltip: 'Back to Home',
                      ),
                      const Spacer(),
                      Text(
                        _todayStr(),
                        style: const TextStyle(
                          color: _kDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _fetchPosts(silent: false),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: _kDark,
                          size: 22,
                        ),
                        tooltip: 'Refresh forums',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'For',
                          style: GoogleFonts.lexend(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: _kDark,
                          ),
                        ),
                        TextSpan(
                          text: 'u',
                          style: GoogleFonts.caveat(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF86C58C),
                          ),
                        ),
                        TextSpan(
                          text: 'ms',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            color: _kPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A safe space to share and connect',
                    style: TextStyle(color: _kSubtle, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('All posts'),
                        selected: !_showMineOnly,
                        onSelected: (_) =>
                            setState(() => _showMineOnly = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('My posts'),
                        selected: _showMineOnly,
                        onSelected: (_) => setState(() => _showMineOnly = true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
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
                    child: activePost == null
                        ? _ForumListView(
                            key: const ValueKey('forum-list'),
                            posts: visiblePosts,
                            companionId: widget.companionId,
                            fabExpanded: _fabExpanded,
                            onPostTap: (i) =>
                                _openPostDetail(visiblePosts[i].id),
                            onLikeTap: (i) => _toggleLike(visiblePosts[i].id),
                            onReportTap: (i) =>
                                _showReportDialog(visiblePosts[i].id),
                            onExpandFab: () =>
                                setState(() => _fabExpanded = true),
                            onCollapseFab: () =>
                                setState(() => _fabExpanded = false),
                            onCreatePost: _showComposerDialog,
                          )
                        : _ForumDetailView(
                            key: const ValueKey('forum-detail'),
                            post: activePost,
                            onClose: _closePostDetail,
                            onLikeTap: () => _toggleLike(activePost.id),
                            onReportTap: () => _showReportDialog(activePost.id),
                            onAddComment: _addComment,
                          ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _ForumBottomNav(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
      ),
    );
  }
}

class _ForumListView extends StatelessWidget {
  final List<_ForumPost> posts;
  final int companionId;
  final bool fabExpanded;
  final ValueChanged<int> onPostTap;
  final ValueChanged<int> onLikeTap;
  final ValueChanged<int> onReportTap;
  final VoidCallback onExpandFab;
  final VoidCallback onCollapseFab;
  final VoidCallback onCreatePost;

  const _ForumListView({
    super.key,
    required this.posts,
    required this.companionId,
    required this.fabExpanded,
    required this.onPostTap,
    required this.onLikeTap,
    required this.onReportTap,
    required this.onExpandFab,
    required this.onCollapseFab,
    required this.onCreatePost,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          ),
          child: posts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 62,
                        color: Color(0xFFAFAFB4),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No posts yet',
                        style: TextStyle(
                          color: _kDark,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tap + to share the first supportive post.',
                        style: TextStyle(color: _kSubtle, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 114),
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) {
                    return _PostCard(
                      post: posts[i],
                      onTap: () => onPostTap(i),
                      onLikeTap: () => onLikeTap(i),
                      onReportTap: () => onReportTap(i),
                    );
                  },
                ),
        ),
        if (fabExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: onCollapseFab,
              child: Container(color: Colors.transparent),
            ),
          ),
        Positioned(
          bottom: 24,
          right: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: fabExpanded
                ? Row(
                    key: const ValueKey('fab-expanded'),
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Image.asset(
                        'assets/doodle$companionId.png',
                        width: 72,
                        height: 72,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _kDark,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Let\'s support someone today!',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: onCollapseFab,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: onCreatePost,
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0x22000000),
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.add,
                                    color: _kDark,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  )
                : GestureDetector(
                    key: const ValueKey('fab-main'),
                    onTap: onExpandFab,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: _kPurple,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x44A076F9),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 34,
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
  final VoidCallback onClose;
  final VoidCallback onLikeTap;
  final VoidCallback onReportTap;
  final Future<void> Function(String) onAddComment;

  const _ForumDetailView({
    super.key,
    required this.post,
    required this.onClose,
    required this.onLikeTap,
    required this.onReportTap,
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
    final post = widget.post;
    return Container(
      color: _kHeaderBg,
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
                        onTap: () {},
                        onLikeTap: widget.onLikeTap,
                        onReportTap: widget.onReportTap,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, color: _kSubtle),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...post.comments.map(
                  (c) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          c.moodAsset,
                          width: 32,
                          height: 32,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            color: _kSubtle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.text,
                            style: const TextStyle(
                              color: _kDark,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      enabled: !_submittingComment,
                      decoration: InputDecoration(
                        hintText: 'Add a supportive comment',
                        hintStyle: const TextStyle(color: Color(0xFFB3B3B8)),
                        filled: true,
                        fillColor: Colors.white,
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
                  GestureDetector(
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
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: _kPurple,
                        shape: BoxShape.circle,
                      ),
                      child: _submittingComment
                          ? const Padding(
                              padding: EdgeInsets.all(12),
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
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final VoidCallback onReportTap;

  const _PostCard({
    required this.post,
    required this.onTap,
    required this.onLikeTap,
    required this.onReportTap,
    this.compactText = true,
  });

  @override
  Widget build(BuildContext context) {
    final likeColor = post.likedByMe ? Colors.red : _kSubtle;
    return TapScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: post.cardColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              post.doodleAsset,
              width: compactText ? 62 : 74,
              height: compactText ? 62 : 74,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.face_outlined, size: 56, color: _kSubtle),
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
                      color: _kDark,
                      fontSize: compactText ? 15.5 : 18,
                      height: compactText ? 1.15 : 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: compactText ? 4 : 6),
                  Text(
                    compactText
                        ? post.content
                        : '${post.content}\nPosted by ${post.author}',
                    maxLines: compactText ? 3 : null,
                    overflow: compactText ? TextOverflow.ellipsis : null,
                    style: TextStyle(
                      color: _kDark,
                      fontSize: compactText ? 11.5 : 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.mode_comment_outlined,
                        color: _kSubtle,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentCount}',
                        style: const TextStyle(
                          color: _kSubtle,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: onLikeTap,
                        behavior: HitTestBehavior.opaque,
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
                      GestureDetector(
                        onTap: onReportTap,
                        behavior: HitTestBehavior.opaque,
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFF111111),
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

class _ForumBottomNav extends StatelessWidget {
  final String userName;
  final int companionId;
  final String companionName;

  const _ForumBottomNav({
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(
        icon: Icons.calendar_month_outlined,
        label: 'Calendar',
        onTap: () => Navigator.of(context).pushAndRemoveUntil(
          FadeSlideRoute(
            page: CalendarScreen(
              userName: userName,
              companionId: companionId,
              companionName: companionName,
            ),
          ),
          (_) => false,
        ),
      ),
      _NavItem(
        icon: Icons.book_outlined,
        label: 'Journal',
        onTap: () => Navigator.of(context).pushAndRemoveUntil(
          FadeSlideRoute(
            page: JournalScreen(
              userName: userName,
              companionId: companionId,
              companionName: companionName,
            ),
          ),
          (_) => false,
        ),
      ),
      _NavItem(
        icon: Icons.home_rounded,
        label: 'Home',
        onTap: () => Navigator.of(context).pushAndRemoveUntil(
          FadeSlideRoute(
            page: HomeScreen(
              userName: userName,
              companionId: companionId,
              companionName: companionName,
            ),
          ),
          (_) => false,
        ),
      ),
      const _NavItem(
        icon: Icons.chat_bubble_rounded,
        label: 'Forums',
        active: true,
      ),
      const _NavItem(icon: Icons.folder_outlined, label: 'Resources'),
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 62, color: const Color(0xFFAFAFB4)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: _kDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: _kSubtle, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });
}
