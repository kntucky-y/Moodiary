import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../calendar/calendar_screen.dart';
import '../journal/journal_screen.dart';
import '../forums/forums_screen.dart';
import '../home/home_screen.dart';
import '../../utils/transitions.dart';
import 'friend_chat_screen.dart';

const _kBaseUrl = 'https://moodiary-production.up.railway.app';
const _kPurple = Color(0xFFA076F9);
const _kDark = Color(0xFF2C2C2C);
const _kHeaderBg = Color(0xFFF0ECFF);
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
  String? _token;
  List<_FriendSummary> _friends = [];
  List<_FriendRequest> _incoming = [];
  List<_FriendRequest> _outgoing = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    await _loadFriends();
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

  Future<void> _sendRequest(String email) async {
    if (_token == null) return;
    try {
      final resp = await http.post(
        Uri.parse('$_kBaseUrl/api/friends/request'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );
      if (resp.statusCode == 201) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Friend request sent!')));
        }
        await _loadFriends();
      } else {
        final data = jsonDecode(resp.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? 'Request failed')),
        );
      }
    } catch (err) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send: $err')));
    }
  }

  Future<void> _acceptRequest(String id) async {
    if (_token == null) return;
    final resp = await http.post(
      Uri.parse('$_kBaseUrl/api/friends/$id/accept'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (resp.statusCode == 200) {
      await _loadFriends();
    } else {
      final data = jsonDecode(resp.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error'] ?? 'Unable to accept')),
      );
    }
  }

  Future<void> _rejectRequest(String id) async {
    if (_token == null) return;
    final resp = await http.post(
      Uri.parse('$_kBaseUrl/api/friends/$id/reject'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (resp.statusCode == 200) {
      await _loadFriends();
    } else {
      final data = jsonDecode(resp.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error'] ?? 'Unable to update request')),
      );
    }
  }

  void _openAddFriendSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddFriendSheet(onSubmit: _sendRequest),
    );
  }

  void _openChat(_FriendSummary friend) {
    Navigator.of(context).push(
      FadeSlideRoute(
        page: FriendChatScreen(
          friendshipId: friend.id,
          friendName: friend.name,
          friendEmail: friend.email,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kHeaderBg,
      body: Column(
        children: [
          _FriendsHeader(onAddFriend: _openAddFriendSheet),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
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
                          const Text(
                            'Buddies',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: _kDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_friends.isEmpty)
                            const _EmptyFriends()
                          else
                            ..._friends.map(
                              (friend) => _FriendCard(
                                friend: friend,
                                onTap: () => _openChat(friend),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _FriendsBottomNav(
        userName: widget.userName,
        companionId: widget.companionId,
        companionName: widget.companionName,
      ),
    );
  }
}

class _FriendSummary {
  final String id;
  final String name;
  final String email;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  _FriendSummary({
    required this.id,
    required this.name,
    required this.email,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory _FriendSummary.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'] as Map<String, dynamic>?;
    final friend = json['friend'] as Map<String, dynamic>? ?? {};
    return _FriendSummary(
      id: json['id'].toString(),
      name: friend['name'] as String? ?? 'Friend',
      email: friend['email'] as String? ?? '',
      lastMessage: last != null ? last['text'] as String? : null,
      lastMessageAt: last != null && last['createdAt'] != null
          ? DateTime.parse(last['createdAt'] as String).toLocal()
          : null,
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

  const _FriendsHeader({required this.onAddFriend});

  @override
  Widget build(BuildContext context) {
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
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Icon(Icons.menu, color: _kDark),
                ),
                const Spacer(),
                Text(
                  formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _kDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: _kDark,
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
            const Text(
              'See how your friends are feeling and give them support.',
              style: TextStyle(color: _kSubtle, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddFriend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _kPurple,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Add new friend'),
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

  const _FriendCard({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FB),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _kPurple.withOpacity(0.15),
              child: Text(
                friend.name.isEmpty ? '?' : friend.name[0].toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _kPurple,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: _kDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    friend.lastMessage ?? 'No messages yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kSubtle, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (friend.lastMessageAt != null)
              Text(
                _formatDate(friend.lastMessageAt!),
                style: const TextStyle(color: _kSubtle, fontSize: 11),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: _kDark,
          ),
        ),
        const SizedBox(height: 8),
        ...requests.map(
          (req) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _kDark,
                        ),
                      ),
                      Text(
                        req.email,
                        style: const TextStyle(color: _kSubtle, fontSize: 12),
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
          const Text(
            'Add a friend',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Friend email',
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.sentiment_satisfied_alt, color: _kSubtle, size: 48),
          SizedBox(height: 8),
          Text('No friends yet - invite someone!'),
        ],
      ),
    );
  }
}

class _FriendsBottomNav extends StatelessWidget {
  final String userName;
  final int companionId;
  final String companionName;

  const _FriendsBottomNav({
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  Widget build(BuildContext context) {
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
          _NavBtn(
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
          _NavBtn(
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
          const _NavBtn(
            icon: Icons.people_alt_rounded,
            label: 'Friends',
            active: true,
          ),
          _NavBtn(
            icon: Icons.chat_bubble_outline,
            label: 'Forums',
            onTap: () => Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(
                page: ForumsScreen(
                  userName: userName,
                  companionId: companionId,
                  companionName: companionName,
                ),
              ),
              (_) => false,
            ),
          ),
          const _NavBtn(icon: Icons.folder_outlined, label: 'Resources'),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _NavBtn({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
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
