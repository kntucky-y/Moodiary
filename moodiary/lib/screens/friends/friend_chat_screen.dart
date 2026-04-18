import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../services/auth_service.dart';
import '../forums/forums_screen.dart';
import '../../utils/transitions.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/avatar_utils.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_profile_popup.dart';

const _kBaseUrl = kBackendBaseUrl;
const _kPurple = Color(0xFFA076F9);
const _kBubbleMine = Color(0xFF4338CA);

class FriendChatScreen extends StatefulWidget {
  final String friendshipId;
  final String friendUserId;
  final String friendName;
  final String friendEmail;
  final String? friendAvatarUrl;
  final String authToken;
  final String userName;
  final int companionId;
  final String companionName;

  const FriendChatScreen({
    super.key,
    required this.friendshipId,
    required this.friendUserId,
    required this.friendName,
    required this.friendEmail,
    this.friendAvatarUrl,
    required this.authToken,
    required this.userName,
    required this.companionId,
    required this.companionName,
  });

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final List<_FriendMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  String? _token;
  String? _userId;
  String _userName = '';
  int _companionId = 1;
  String _companionName = 'Companion';
  io.Socket? _socket;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _token = widget.authToken.trim().isEmpty ? null : widget.authToken;
    _userName = widget.userName;
    _companionId = widget.companionId;
    _companionName = widget.companionName;
    _userId = _deriveUserIdFromToken(_token ?? '');
    _connectSocket();
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final resp = await http
          .get(
            Uri.parse('$_kBaseUrl/api/friends/${widget.friendshipId}/messages'),
            headers: {'Authorization': 'Bearer $_token'},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        setState(() {
          _messages
            ..clear()
            ..addAll(
              data.map(
                (j) =>
                    _FriendMessage.fromJson(j as Map<String, dynamic>, _userId),
              ),
            );
          _loading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _connectSocket() {
    if (_token == null) return;
    _socket = io.io(
      _kBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': _token})
          .disableAutoConnect()
          .build(),
    );

    _socket!
      ..connect()
      ..onConnect((_) {
        _socket?.emit('friends:join', {'friendshipId': widget.friendshipId});
      })
      ..on('friends:message', (data) {
        if (data is Map && data['friendshipId'] == widget.friendshipId) {
          final incoming = _FriendMessage.fromJson(
            Map<String, dynamic>.from(data),
            _userId,
          );
          setState(() {
            final exactIndex = _messages.indexWhere((m) => m.id == incoming.id);
            if (exactIndex != -1) {
              _messages[exactIndex] = incoming;
              return;
            }
            final pendingIndex = _messages.lastIndexWhere(
              (m) =>
                  m.pending &&
                  m.text == incoming.text &&
                  (incoming.isMine || _userId == null) &&
                  (incoming.createdAt.difference(m.createdAt).abs() <
                      const Duration(seconds: 15)),
            );
            if (pendingIndex != -1) {
              _messages[pendingIndex] = incoming;
            } else {
              _messages.add(incoming);
            }
          });
          _scrollToBottom();
        }
      })
      ..on('friends:removed', (data) {
        if (data is Map && data['friendshipId'] == widget.friendshipId) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.friendName} is no longer connected.'),
            ),
          );
          Navigator.of(context).pop();
        }
      })
      ..on('friends:error', (data) {
        if (!mounted) return;
        final isMap = data is Map;
        final sameRoom =
            !isMap ||
            data['friendshipId'] == null ||
            data['friendshipId'] == widget.friendshipId;
        if (!sameRoom) return;
        final message = isMap && data['error'] is String
            ? data['error'] as String
            : null;
        final copy = (message == null || message.isEmpty)
            ? 'Chat connection issue. Please try again.'
            : message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(copy)));
      })
      ..onDisconnect((_) {
        // no-op
      });
  }

  Future<void> _sendMessage() async {
    final text = _input.text.trim();
    if (text.isEmpty || _token == null) return;
    setState(() => _sending = true);
    _input.clear();

    final optimistic = _FriendMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      createdAt: DateTime.now(),
      isMine: true,
      pending: true,
    );

    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    try {
      final resp = await http
          .post(
            Uri.parse('$_kBaseUrl/api/friends/${widget.friendshipId}/messages'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 201) {
        throw Exception('Failed to send message');
      }

      final created = _FriendMessage.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>,
        _userId,
      );

      if (mounted) {
        setState(() {
          final pendingIndex = _messages.lastIndexWhere(
            (m) => m.id == optimistic.id,
          );
          if (pendingIndex != -1) {
            _messages[pendingIndex] = created;
          } else if (_messages.every((m) => m.id != created.id)) {
            _messages.add(created);
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == optimistic.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message. Please retry.')),
      );
      _input.text = text;
      _input.selection = TextSelection.fromPosition(
        TextPosition(offset: _input.text.length),
      );
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 40,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _socket?.emit('friends:leave', {'friendshipId': widget.friendshipId});
    _socket?.dispose();
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _deriveUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalizedPayload = base64Url.normalize(parts[1]);
      final decodedPayload = utf8.decode(base64Url.decode(normalizedPayload));
      final payload = jsonDecode(decodedPayload);
      if (payload is! Map<String, dynamic>) return null;
      final candidate = payload['userId'] ?? payload['id'] ?? payload['_id'];
      if (candidate == null) return null;
      final userId = candidate.toString();
      return userId.isEmpty ? null : userId;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              friendUserId: widget.friendUserId,
              name: widget.friendName,
              email: widget.friendEmail,
              friendAvatarUrl: widget.friendAvatarUrl,
              onOpenForumPost: (postId) async {
                if (!context.mounted) return;
                Navigator.of(context).push(
                  FadeSlideRoute(
                    page: ForumsScreen(
                      userName: _userName,
                      companionId: _companionId,
                      companionName: _companionName,
                      initialPostId: postId,
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: GlassContainer(
                blurSigma: context.mdGlassBlurMedium,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                backgroundColor: context.mdGlassSurface,
                borderColor: context.mdGlassBorder,
                padding: EdgeInsets.zero,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? _EmptyChat(friendName: widget.friendName)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return _ChatBubble(
                            message: message,
                            friendAvatarUrl: widget.friendAvatarUrl,
                          );
                        },
                      ),
              ),
            ),
            _MessageComposer(
              controller: _input,
              onSend: _sendMessage,
              sending: _sending,
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendMessage {
  final String id;
  final String text;
  final DateTime createdAt;
  final bool isMine;
  final bool pending;

  _FriendMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.isMine,
    this.pending = false,
  });

  factory _FriendMessage.fromJson(Map<String, dynamic> json, String? viewerId) {
    final createdRaw = json['createdAt'];
    final createdAt = createdRaw is String
        ? DateTime.parse(createdRaw).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(createdRaw as int).toLocal();
    final sender = json['sender']?.toString();
    final rawId = json['id'] ?? json['_id'];
    return _FriendMessage(
      id: rawId != null
          ? rawId.toString()
          : 'remote-${DateTime.now().millisecondsSinceEpoch}',
      text: json['text'] as String,
      createdAt: createdAt,
      isMine: sender != null && sender == viewerId,
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _FriendMessage message;
  final String? friendAvatarUrl;

  const _ChatBubble({required this.message, this.friendAvatarUrl});

  @override
  Widget build(BuildContext context) {
    final friendBubble = context.mdSecondarySurface;
    final friendText = context.mdPrimaryText;
    final secondaryText = context.mdSecondaryText;
    final alignment = message.isMine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bubbleColor = message.isMine ? _kBubbleMine : friendBubble;
    final textColor = message.isMine ? Colors.white : friendText;

    return Align(
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isMine)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: CircleAvatar(
                radius: 12,
                backgroundImage: avatarImageProvider(friendAvatarUrl),
                child: avatarImageProvider(friendAvatarUrl) == null
                    ? const Icon(Icons.person, size: 12)
                    : null,
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: message.isMine ? const Radius.circular(4) : null,
                bottomLeft: message.isMine ? null : const Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: message.isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
                if (message.pending)
                  Text(
                    'sending...',
                    style: TextStyle(
                      color: message.isMine ? Colors.white70 : secondaryText,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ChatHeader extends StatelessWidget {
  final String friendUserId;
  final String name;
  final String email;
  final String? friendAvatarUrl;
  final Future<void> Function(String postId)? onOpenForumPost;

  const _ChatHeader({
    required this.friendUserId,
    required this.name,
    required this.email,
    this.friendAvatarUrl,
    this.onOpenForumPost,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryText = context.mdSecondaryText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _kPurple,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              if (friendUserId.isEmpty) return;
              final selectedPostId = await showUserProfilePopup(
                context,
                userId: friendUserId,
              );
              if (selectedPostId == null) return;
              final openForumPost = onOpenForumPost;
              if (openForumPost != null) {
                await openForumPost(selectedPostId);
              }
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: avatarImageProvider(friendAvatarUrl),
                  child: avatarImageProvider(friendAvatarUrl) == null
                      ? const Icon(Icons.person, size: 18)
                      : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: _kPurple,
                      ),
                    ),
                    Text(
                      email,
                      style: TextStyle(color: secondaryText, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  const _MessageComposer({
    required this.controller,
    required this.onSend,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: GlassContainer(
        blurSigma: context.mdGlassBlurMedium,
        backgroundColor: context.mdGlassSurfaceStrong,
        borderColor: context.mdGlassBorder,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(color: context.mdPrimaryText),
                decoration: InputDecoration(
                  hintText: 'Send some support...',
                  hintStyle: TextStyle(color: context.mdSecondaryText),
                  filled: true,
                  fillColor: context.mdInputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: sending ? null : onSend,
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                width: 48,
                height: 48,
                child: GlassContainer(
                  blurSigma: context.mdGlassBlurSmall,
                  borderRadius: BorderRadius.circular(24),
                  backgroundColor: sending
                      ? _kPurple.withValues(alpha: 0.44)
                      : _kPurple.withValues(alpha: 0.68),
                  borderColor: context.mdGlassBorder,
                  padding: EdgeInsets.zero,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String friendName;

  const _EmptyChat({required this.friendName});

  @override
  Widget build(BuildContext context) {
    final secondaryText = context.mdSecondaryText;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pets, size: 64, color: Color(0xFFCBD5F5)),
          const SizedBox(height: 12),
          Text(
            'Say hi to $friendName!',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: _kPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Offer a little encouragement today.',
            style: TextStyle(color: secondaryText),
          ),
        ],
      ),
    );
  }
}
