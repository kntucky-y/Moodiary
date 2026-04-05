import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/calendar_screen.dart';
import '../journal/journal_screen.dart';
import '../forums/forums_screen.dart';
import '../home/home_screen.dart';
import '../profile/user_profile_screen.dart';
import '../companion/companion_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/local_notifications_service.dart';
import '../../utils/transitions.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/realtime_notifications.dart';
import '../../services/theme_controller.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/avatar_utils.dart';
import '../../widgets/user_profile_popup.dart';
import 'user_discovery_screen.dart';
import 'friend_chat_screen.dart';

const _kBaseUrl = 'https://moodiary-production.up.railway.app';
const _kPurple = Color(0xFFA076F9);
const _kSubtle = Color(0xFF9CA3AF);

class FriendsScreen extends StatefulWidget {
  final String userName;
  final int companionId;
  final String companionName;

  const FriendsScreen({
    super.key,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  bool _sidebarOpen = false;
  String? _token;
  late String _currentUserName;
  List<_FriendSummary> _friends = [];
  List<_FriendRequest> _incoming = [];
  List<_FriendRequest> _outgoing = [];
  StreamSubscription<Map<String, dynamic>>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _currentUserName = widget.userName;
    _notificationSub = RealtimeNotifications.instance.stream.listen(
      _handleNotification,
    );
    _init();
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final latestName = prefs.getString('user_name')?.trim();
    if (latestName != null && latestName.isNotEmpty) {
      _currentUserName = latestName;
    }
    await RealtimeNotifications.instance.ensureConnected(token: _token);
    await _loadFriends();
  }

  Future<void> _refreshUserNameFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final latestName = prefs.getString('user_name')?.trim();
    if (!mounted || latestName == null || latestName.isEmpty) return;
    if (latestName == _currentUserName) return;
    setState(() {
      _currentUserName = latestName;
    });
  }

  void _handleNotification(Map<String, dynamic> payload) {
    if (!mounted) return;
    final type = payload['type'];
    if (type == 'friend_removed') {
      final friendshipId = payload['friendshipId']?.toString();
      if (friendshipId == null) return;
      setState(() {
        _friends.removeWhere((f) => f.id == friendshipId);
      });
      return;
    }

    if (type == 'friend_message') {
      final friendshipId = payload['friendshipId']?.toString();
      if (friendshipId == null) return;
      final index = _friends.indexWhere((f) => f.id == friendshipId);
      if (index == -1) return;
      final text = payload['text'] as String?;
      final createdRaw = payload['createdAt'];
      DateTime? createdAt;
      if (createdRaw is String) {
        createdAt = DateTime.tryParse(createdRaw)?.toLocal();
      } else if (createdRaw is int) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(createdRaw).toLocal();
      }
      if (text == null && createdAt == null) return;
      setState(() {
        final friend = _friends[index];
        _friends[index] = friend.copyWith(
          lastMessage: text ?? friend.lastMessage,
          lastMessageAt: createdAt ?? friend.lastMessageAt,
        );
      });
    }
  }

  Future<void> _loadFriends() async {
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/api/friends'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final friends = (data['friends'] as List<dynamic>)
            .map((j) => _FriendSummary.fromJson(j as Map<String, dynamic>))
            .toList();
        final pending = data['pending'] as Map<String, dynamic>? ?? {};
        final incoming = (pending['incoming'] as List<dynamic>? ?? [])
            .map(
              (j) => _FriendRequest.fromJson(
                j as Map<String, dynamic>,
                incoming: true,
              ),
            )
            .toList();
        final outgoing = (pending['outgoing'] as List<dynamic>? ?? [])
            .map(
              (j) => _FriendRequest.fromJson(
                j as Map<String, dynamic>,
                incoming: false,
              ),
            )
            .toList();
        setState(() {
          _friends = friends;
          _incoming = incoming;
          _outgoing = outgoing;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _acceptRequest(String id) async {
    if (_token == null) return;
    final resp = await http.post(
      Uri.parse('$_kBaseUrl/api/friends/$id/accept'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (resp.statusCode == 200) {
      if (!mounted) return;
      await _loadFriends();
    } else {
      final message = _responseErrorMessage(resp, fallback: 'Unable to accept');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _rejectRequest(String id) async {
    if (_token == null) return;
    final resp = await http.post(
      Uri.parse('$_kBaseUrl/api/friends/$id/reject'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (resp.statusCode == 200) {
      if (!mounted) return;
      await _loadFriends();
    } else {
      final message = _responseErrorMessage(
        resp,
        fallback: 'Unable to update request',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _unfriend(String friendshipId) async {
    if (_token == null) return;
    try {
      final resp = await http.delete(
        Uri.parse('$_kBaseUrl/api/friends/$friendshipId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Friend removed.')));
        await _loadFriends();
      } else {
        final message = _responseErrorMessage(
          resp,
          fallback: 'Unable to remove friend',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove friend right now. Please try again.'),
        ),
      );
    }
  }

  Future<void> _confirmUnfriend(_FriendSummary friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'Unfriending ${friend.name} will delete your chat history. You can always reconnect later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _unfriend(friend.id);
    }
  }

  String _responseErrorMessage(http.Response resp, {required String fallback}) {
    if (resp.body.isEmpty) {
      return '$fallback (${resp.statusCode})';
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        final value = decoded['error'] ?? decoded['message'];
        if (value is String && value.trim().isNotEmpty) {
          return value;
        }
      }
    } catch (_) {
      // Ignore parsing issues and fall back to generic copy.
    }
    return '$fallback (${resp.statusCode})';
  }

  void _closeSidebar() => setState(() => _sidebarOpen = false);

  void _openScreen(Widget page) {
    _closeSidebar();
    Navigator.of(context).push(FadeSlideRoute(page: page));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
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

  void _openAddFriendSheet() {
    Navigator.of(
      context,
    ).push(FadeSlideRoute(page: const UserDiscoveryScreen()));
  }

  void _openChat(_FriendSummary friend) {
    final token = _token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat is not available right now.')),
      );
      return;
    }
    Navigator.of(context).push(
      FadeSlideRoute(
        page: FriendChatScreen(
          friendshipId: friend.id,
          friendUserId: friend.friendUserId,
          friendName: friend.name,
          friendEmail: friend.email,
          friendAvatarUrl: friend.avatarUrl,
          authToken: token,
          userName: _currentUserName,
          companionId: widget.companionId,
          companionName: widget.companionName,
        ),
      ),
    );
  }

  Future<void> _openFriendProfile(_FriendSummary friend) async {
    final selectedPostId = await showUserProfilePopup(
      context,
      userId: friend.friendUserId,
    );
    if (selectedPostId == null || !mounted) return;
    Navigator.of(context).push(
      FadeSlideRoute(
        page: ForumsScreen(
          userName: _currentUserName,
          companionId: widget.companionId,
          companionName: widget.companionName,
          initialPostId: selectedPostId,
        ),
      ),
    );
  }

  Future<void> _showFriendActions(_FriendSummary friend) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.mdSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('View profile'),
                onTap: () => Navigator.of(ctx).pop('profile'),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: const Text('Chat'),
                onTap: () => Navigator.of(ctx).pop('chat'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'profile') {
      await _openFriendProfile(friend);
    } else if (action == 'chat') {
      _openChat(friend);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          Column(
            children: [
              _FriendsHeader(
                onAddFriend: _openAddFriendSheet,
                onOpenSidebar: () => setState(() => _sidebarOpen = true),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.mdSurface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(40),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _loadFriends,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                            children: [
                              if (_incoming.isNotEmpty)
                                _RequestSection(
                                  title: 'Friend requests',
                                  requests: _incoming,
                                  onPrimary: _acceptRequest,
                                  onSecondary: _rejectRequest,
                                ),
                              if (_outgoing.isNotEmpty)
                                _RequestSection(
                                  title: 'Pending invites',
                                  requests: _outgoing,
                                  outgoing: true,
                                  onSecondary: _rejectRequest,
                                ),
                              const SizedBox(height: 12),
                              Text(
                                'Buddies',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: context.mdPrimaryText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_friends.isEmpty)
                                const _EmptyFriends()
                              else
                                ..._friends.map(
                                  (friend) => _FriendCard(
                                    friend: friend,
                                    onTap: () => _showFriendActions(friend),
                                    onUnfriend: () => _confirmUnfriend(friend),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (_sidebarOpen)
            GestureDetector(
              onTap: _closeSidebar,
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
              activeSection: SidebarSection.friends,
              onClose: _closeSidebar,
              onNavigateHome: () async {
                final prefs = await SharedPreferences.getInstance();
                final avatarUrl = prefs.getString('user_avatar_url');
                if (!mounted) return;
                _openScreen(
                  HomeScreen(
                    userName: _currentUserName,
                    companionId: widget.companionId,
                    companionName: widget.companionName,
                    initialProfileAvatarUrl: avatarUrl,
                  ),
                );
              },
              onNavigateUserProfile: () async {
                _closeSidebar();
                await Navigator.of(
                  context,
                ).push(FadeSlideRoute(page: const UserProfileScreen()));
                await _refreshUserNameFromPrefs();
              },
              onNavigateCalendar: () => _openScreen(
                CalendarScreen(
                  userName: _currentUserName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateJournal: () => _openScreen(
                JournalScreen(
                  userName: _currentUserName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateFriends: _closeSidebar,
              onNavigateForums: () => _openScreen(
                ForumsScreen(
                  userName: _currentUserName,
                  companionId: widget.companionId,
                  companionName: widget.companionName,
                ),
              ),
              onNavigateSettings: () =>
                  _openScreen(SettingsScreen(userName: _currentUserName)),
              onChangeCompanion: () =>
                  _openScreen(CompanionScreen(userName: _currentUserName)),
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

class _FriendSummary {
  final String id;
  final String friendUserId;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? currentMoodLabel;
  final String? currentMoodAsset;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  _FriendSummary({
    required this.id,
    required this.friendUserId,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.currentMoodLabel,
    this.currentMoodAsset,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory _FriendSummary.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'] as Map<String, dynamic>?;
    final friend = json['friend'] as Map<String, dynamic>? ?? {};
    return _FriendSummary(
      id: json['id'].toString(),
      friendUserId: friend['id']?.toString() ?? '',
      name: friend['name'] as String? ?? 'Friend',
      email: friend['email'] as String? ?? '',
      avatarUrl: friend['avatarUrl'] as String?,
      currentMoodLabel:
          (json['currentMood'] as Map<String, dynamic>?)?['label'] as String?,
      currentMoodAsset:
          (json['currentMood'] as Map<String, dynamic>?)?['asset'] as String?,
      lastMessage: last != null ? last['text'] as String? : null,
      lastMessageAt: last != null && last['createdAt'] != null
          ? DateTime.parse(last['createdAt'] as String).toLocal()
          : null,
    );
  }

  _FriendSummary copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? currentMoodLabel,
    String? currentMoodAsset,
    String? lastMessage,
    DateTime? lastMessageAt,
  }) {
    return _FriendSummary(
      id: id,
      friendUserId: friendUserId,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      currentMoodLabel: currentMoodLabel ?? this.currentMoodLabel,
      currentMoodAsset: currentMoodAsset ?? this.currentMoodAsset,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}

class _FriendRequest {
  final String id;
  final String name;
  final String email;
  final bool incoming;

  _FriendRequest({
    required this.id,
    required this.name,
    required this.email,
    required this.incoming,
  });

  factory _FriendRequest.fromJson(
    Map<String, dynamic> json, {
    required bool incoming,
  }) {
    final friend = json['friend'] as Map<String, dynamic>? ?? {};
    return _FriendRequest(
      id: json['id'].toString(),
      name: friend['name'] as String? ?? 'Friend',
      email: friend['email'] as String? ?? '',
      incoming: incoming,
    );
  }
}

class _FriendsHeader extends StatelessWidget {
  final VoidCallback onAddFriend;
  final VoidCallback onOpenSidebar;

  const _FriendsHeader({
    required this.onAddFriend,
    required this.onOpenSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    final now = DateTime.now();
    final formatted =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onOpenSidebar,
                  child: Icon(Icons.menu, color: primaryText),
                ),
                const Spacer(),
                Text(
                  formatted,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
                children: [
                  TextSpan(text: 'Bu'),
                  TextSpan(
                    text: 'dd',
                    style: TextStyle(color: Color(0xFF60A5FA)),
                  ),
                  TextSpan(text: 'ies'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'See how your friends are feeling and give them support.',
              style: TextStyle(color: secondaryText, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddFriend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.mdSurface,
                  foregroundColor: _kPurple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Find friends'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final _FriendSummary friend;
  final VoidCallback onTap;
  final VoidCallback? onUnfriend;

  const _FriendCard({
    required this.friend,
    required this.onTap,
    this.onUnfriend,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.mdSecondarySurface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _kPurple.withValues(alpha: 0.15),
              backgroundImage: avatarImageProvider(friend.avatarUrl),
              child: avatarImageProvider(friend.avatarUrl) == null
                  ? Text(
                      friend.name.isEmpty ? '?' : friend.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _kPurple,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (friend.currentMoodLabel != null &&
                      friend.currentMoodAsset != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _kPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            friend.currentMoodAsset!,
                            width: 18,
                            height: 18,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.sentiment_satisfied_alt_outlined,
                                  size: 16,
                                  color: _kPurple,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            friend.currentMoodLabel!,
                            style: TextStyle(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    friend.lastMessage ?? 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondaryText, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (friend.lastMessageAt != null)
                  Text(
                    _formatDate(friend.lastMessageAt!),
                    style: TextStyle(color: secondaryText, fontSize: 11),
                  ),
                if (friend.lastMessageAt != null && onUnfriend != null)
                  const SizedBox(height: 4),
                if (onUnfriend != null)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.more_horiz, color: _kSubtle),
                    tooltip: 'Friend actions',
                    onSelected: (value) {
                      if (value == 'unfriend') {
                        onUnfriend?.call();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'unfriend', child: Text('Unfriend')),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$month/$day';
  }
}

class _RequestSection extends StatelessWidget {
  final String title;
  final List<_FriendRequest> requests;
  final bool outgoing;
  final ValueChanged<String>? onPrimary;
  final ValueChanged<String>? onSecondary;

  const _RequestSection({
    required this.title,
    required this.requests,
    this.outgoing = false,
    this.onPrimary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: primaryText,
          ),
        ),
        const SizedBox(height: 8),
        ...requests.map(
          (req) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.mdSecondarySurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryText,
                        ),
                      ),
                      Text(
                        req.email,
                        style: TextStyle(color: secondaryText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!outgoing)
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => onPrimary?.call(req.id),
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                      ),
                      IconButton(
                        onPressed: () => onSecondary?.call(req.id),
                        icon: const Icon(
                          Icons.cancel_rounded,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  )
                else
                  TextButton(
                    onPressed: () => onSecondary?.call(req.id),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _AddFriendSheet extends StatefulWidget {
  final Future<void> Function(String) onSubmit;

  const _AddFriendSheet({required this.onSubmit});

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (email.isEmpty) return;
    setState(() => _sending = true);
    await widget.onSubmit(email);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Add a friend',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Friend email',
              filled: true,
              fillColor: context.mdInputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send invite'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: context.mdSecondarySurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sentiment_satisfied_alt, color: secondaryText, size: 48),
          const SizedBox(height: 8),
          Text(
            'No friends yet - invite someone!',
            style: TextStyle(color: primaryText),
          ),
        ],
      ),
    );
  }
}
