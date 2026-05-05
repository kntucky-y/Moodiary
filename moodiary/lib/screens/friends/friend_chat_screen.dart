import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../services/auth_service.dart';
import '../../services/realtime_notifications.dart';
import '../forums/forums_screen.dart';
import '../../utils/transitions.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/avatar_utils.dart';
import '../../widgets/glass.dart';
import '../../widgets/user_profile_popup.dart';

const _kBaseUrl = kBackendBaseUrl;
const _kPurple = Color(0xFFA076F9);
const _kBubbleMine = Color(0xFF4338CA);
const _kMaxMessageLength = 1000;

enum _ChatMenuAction { search, clearChat }

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
  final Map<String, ImageProvider<Object>> _avatarImageCache = {};
  bool _loading = true;
  String? _token;
  String? _userId;
  String _userName = '';
  int _companionId = 1;
  String _companionName = 'Companion';
  io.Socket? _socket;
  bool _sending = false;
  String? _highlightedMessageId;
  bool _isTyping = false;
  bool _friendTyping = false;
  Timer? _typingTimer;
  Timer? _friendTypingTimer;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _notificationSub = RealtimeNotifications.instance.stream.listen(
      _handleRealtimeNotification,
    );
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
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': _token})
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(800)
          .setReconnectionDelayMax(4000)
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
          RealtimeNotifications.instance.emitLocal({
            'type': 'friend_message',
            'friendshipId': widget.friendshipId,
            'text': incoming.text,
            'createdAt': incoming.createdAt.toIso8601String(),
          });
          _scrollToBottom();
        }
      })
      ..on('friends:message:update', (data) {
        if (data is Map && data['friendshipId'] == widget.friendshipId) {
          final updated = _FriendMessage.fromJson(
            Map<String, dynamic>.from(data),
            _userId,
          );
          setState(() {
            final index = _messages.indexWhere((m) => m.id == updated.id);
            if (index != -1) {
              _messages[index] = updated;
            }
          });
        }
      })
      ..on('friends:typing', (data) {
        if (data is! Map || data['friendshipId'] != widget.friendshipId) {
          return;
        }
        final senderId = data['userId']?.toString();
        if (senderId == null || senderId == _userId) return;
        final isTyping = data['isTyping'] == true;
        _friendTypingTimer?.cancel();
        if (isTyping) {
          _friendTypingTimer = Timer(const Duration(seconds: 3), () {
            if (!mounted) return;
            setState(() => _friendTyping = false);
          });
        }
        if (!mounted) return;
        setState(() => _friendTyping = isTyping);
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
    if (text.length > _kMaxMessageLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Message is too long (max $_kMaxMessageLength characters).',
          ),
        ),
      );
      return;
    }
    _stopTyping();
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
      RealtimeNotifications.instance.emitLocal({
        'type': 'friend_message',
        'friendshipId': widget.friendshipId,
        'text': created.text,
        'createdAt': created.createdAt.toIso8601String(),
      });
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

  Future<void> _deleteMessage(_FriendMessage message) async {
    if (_token == null) return;
    try {
      final resp = await http.delete(
        Uri.parse(
          '$_kBaseUrl/api/friends/${widget.friendshipId}/messages/${message.id}',
        ),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _messages.removeWhere((m) => m.id == message.id);
        });
      } else {
        throw Exception('Failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete message.')),
      );
    }
  }

  Future<void> _unsendMessage(_FriendMessage message) async {
    if (_token == null) return;
    try {
      final resp = await http.post(
        Uri.parse(
          '$_kBaseUrl/api/friends/${widget.friendshipId}/messages/${message.id}/unsend',
        ),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final payload = data['message'] as Map<String, dynamic>;
        final updated = _FriendMessage.fromJson(payload, _userId);
        if (!mounted) return;
        setState(() {
          final index = _messages.indexWhere((m) => m.id == updated.id);
          if (index != -1) {
            _messages[index] = updated;
          }
        });
      } else {
        throw Exception('Failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not unsend message.')),
      );
    }
  }

  Future<void> _clearChat() async {
    if (_token == null) return;
    try {
      final resp = await http.post(
        Uri.parse(
          '$_kBaseUrl/api/friends/${widget.friendshipId}/messages/clear',
        ),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _messages.clear();
        });
      } else {
        throw Exception('Failed');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not clear chat.')));
    }
  }

  Future<void> _openSearch() async {
    if (_token == null) return;
    final controller = TextEditingController();
    bool loading = false;
    List<_FriendMessage> results = [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> runSearch() async {
              final q = controller.text.trim();
              if (q.isEmpty) return;
              setModalState(() => loading = true);
              try {
                final resp = await http.get(
                  Uri.parse(
                    '$_kBaseUrl/api/friends/${widget.friendshipId}/messages/search?q=${Uri.encodeComponent(q)}',
                  ),
                  headers: {'Authorization': 'Bearer $_token'},
                );
                if (resp.statusCode == 200) {
                  final data = jsonDecode(resp.body) as Map<String, dynamic>;
                  final raw = (data['results'] as List<dynamic>?) ?? [];
                  results = raw
                      .map(
                        (j) => _FriendMessage.fromJson(
                          j as Map<String, dynamic>,
                          _userId,
                        ),
                      )
                      .toList();
                }
              } catch (_) {
                // ignore
              } finally {
                setModalState(() => loading = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: GlassContainer(
                blurSigma: context.mdGlassBlurMedium,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                backgroundColor: context.mdGlassSurfaceStrong,
                borderColor: context.mdGlassBorder,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => runSearch(),
                            style: TextStyle(color: context.mdPrimaryText),
                            decoration: InputDecoration(
                              hintText: 'Search messages',
                              hintStyle: TextStyle(
                                color: context.mdSecondaryText,
                              ),
                              filled: true,
                              fillColor: context.mdInputFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: runSearch,
                          icon: const Icon(Icons.search),
                          color: _kPurple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(),
                      )
                    else if (results.isEmpty)
                      Text(
                        'No matches yet.',
                        style: TextStyle(color: context.mdSecondaryText),
                      )
                    else
                      SizedBox(
                        height: 260,
                        child: ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, index) {
                            final message = results[index];
                            return ListTile(
                              title: Text(
                                message.isUnsent
                                    ? 'Message unsent'
                                    : message.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_formatTime(message.createdAt)),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                final indexInChat = _messages.indexWhere(
                                  (m) => m.id == message.id,
                                );
                                if (indexInChat != -1) {
                                  setState(() {
                                    _highlightedMessageId = message.id;
                                  });
                                  final listIndex = _listIndexForMessageId(
                                    message.id,
                                  );
                                  _scrollToIndex(listIndex);
                                  Future.delayed(
                                    const Duration(seconds: 3),
                                    () {
                                      if (!mounted) return;
                                      if (_highlightedMessageId == message.id) {
                                        setState(() {
                                          _highlightedMessageId = null;
                                        });
                                      }
                                    },
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final offset = index * 72.0;
    _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  int _listIndexForMessageId(String messageId) {
    final items = _buildChatItems();
    final index = items.indexWhere((item) => item.message?.id == messageId);
    return index == -1 ? 0 : index;
  }

  void _showMessageActions(_FriendMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete for me'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _deleteMessage(message);
                },
              ),
              if (message.isMine && !message.isUnsent && !message.pending)
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('Unsend'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _unsendMessage(message);
                  },
                ),
            ],
          ),
        );
      },
    );
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

  void _handleRealtimeNotification(Map<String, dynamic> payload) {
    if (!mounted) return;
    final type = payload['type']?.toString();
    if (type != 'friend_message') return;
    final friendshipId = payload['friendshipId']?.toString();
    if (friendshipId != widget.friendshipId) return;
    if (_loading) return;
    _loadHistory();
  }

  List<_ChatListItem> _buildChatItems() {
    final items = <_ChatListItem>[];
    DateTime? lastDate;
    for (final message in _messages) {
      final date = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (lastDate == null || !_isSameDay(lastDate, date)) {
        items.add(_ChatListItem.date(date));
        lastDate = date;
      }
      items.add(_ChatListItem.message(message));
    }
    return items;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateHeader(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _handleInputChanged(String value) {
    if (_token == null) return;
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      _emitTyping(true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1600), _stopTyping);
  }

  void _emitTyping(bool isTyping) {
    _socket?.emit('friends:typing', {
      'friendshipId': widget.friendshipId,
      'isTyping': isTyping,
    });
  }

  void _stopTyping() {
    if (!_isTyping) return;
    _isTyping = false;
    _typingTimer?.cancel();
    _emitTyping(false);
  }

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

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$m $suffix';
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    _typingTimer?.cancel();
    _friendTypingTimer?.cancel();
    _stopTyping();
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
    final friendAvatarImage = _cachedAvatarImage(widget.friendAvatarUrl);
    final chatItems = _buildChatItems();
    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              friendUserId: widget.friendUserId,
              name: widget.friendName,
              email: widget.friendEmail,
              friendAvatarImage: friendAvatarImage,
              onMenuAction: (action) async {
                switch (action) {
                  case _ChatMenuAction.search:
                    await _openSearch();
                    break;
                  case _ChatMenuAction.clearChat:
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear chat?'),
                        content: const Text(
                          'This clears the chat only for you.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _clearChat();
                    }
                    break;
                }
              },
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
                        itemCount: chatItems.length + (_friendTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_friendTyping && index == chatItems.length) {
                            return _TypingIndicator(
                              friendAvatarImage: friendAvatarImage,
                            );
                          }
                          final item = chatItems[index];
                          if (item.isDate) {
                            return _DateSeparator(
                              label: _formatDateHeader(item.date!),
                            );
                          }
                          final message = item.message!;
                          return _ChatBubble(
                            message: message,
                            friendAvatarImage: friendAvatarImage,
                            highlighted: message.id == _highlightedMessageId,
                            onLongPress: () => _showMessageActions(message),
                          );
                        },
                      ),
              ),
            ),
            _MessageComposer(
              controller: _input,
              onSend: _sendMessage,
              onChanged: _handleInputChanged,
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
  final bool isUnsent;

  _FriendMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.isMine,
    this.pending = false,
    this.isUnsent = false,
  });

  factory _FriendMessage.fromJson(Map<String, dynamic> json, String? viewerId) {
    final createdRaw = json['createdAt'];
    final createdAt = createdRaw is String
        ? DateTime.parse(createdRaw).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(createdRaw as int).toLocal();
    final sender = json['sender']?.toString();
    final rawId = json['id'] ?? json['_id'];
    final unsentAt = json['unsentAt'];
    final isUnsent = unsentAt is String
        ? unsentAt.isNotEmpty
        : unsentAt != null;
    final text = (json['text'] ?? '').toString();
    return _FriendMessage(
      id: rawId != null
          ? rawId.toString()
          : 'remote-${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      createdAt: createdAt,
      isMine: sender != null && sender == viewerId,
      isUnsent: isUnsent,
    );
  }
}

class _ChatListItem {
  final _FriendMessage? message;
  final DateTime? date;

  const _ChatListItem._({this.message, this.date});

  factory _ChatListItem.message(_FriendMessage message) {
    return _ChatListItem._(message: message);
  }

  factory _ChatListItem.date(DateTime date) {
    return _ChatListItem._(date: date);
  }

  bool get isDate => date != null;
}

class _ChatBubble extends StatelessWidget {
  final _FriendMessage message;
  final ImageProvider<Object>? friendAvatarImage;
  final VoidCallback? onLongPress;
  final bool highlighted;

  const _ChatBubble({
    required this.message,
    this.friendAvatarImage,
    this.onLongPress,
    this.highlighted = false,
  });

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
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!message.isMine)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: CircleAvatar(
                  radius: 12,
                  backgroundImage: friendAvatarImage,
                  child: friendAvatarImage == null
                      ? const Icon(Icons.person, size: 12)
                      : null,
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(18).copyWith(
                      bottomRight: message.isMine
                          ? const Radius.circular(4)
                          : null,
                      bottomLeft: message.isMine
                          ? null
                          : const Radius.circular(4),
                    ),
                    border: highlighted
                        ? Border.all(color: _kPurple.withValues(alpha: 0.6))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: message.isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (message.isUnsent)
                        Text(
                          'Message unsent',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.75),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        Text(
                          message.text,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          textWidthBasis: TextWidthBasis.parent,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                            height: 1.4,
                          ),
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
                            color: message.isMine
                                ? Colors.white70
                                : secondaryText,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$m $suffix';
  }
}

class _TypingIndicator extends StatefulWidget {
  final ImageProvider<Object>? friendAvatarImage;

  const _TypingIndicator({required this.friendAvatarImage});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
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
    final friendBubble = context.mdSecondarySurface;
    final dotColor = context.mdSecondaryText;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 2),
            child: CircleAvatar(
              radius: 12,
              backgroundImage: widget.friendAvatarImage,
              child: widget.friendAvatarImage == null
                  ? const Icon(Icons.person, size: 12)
                  : null,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: friendBubble,
              borderRadius: BorderRadius.circular(
                18,
              ).copyWith(bottomLeft: const Radius.circular(4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, _) {
                    final offset = ((_ctrl.value - i * 0.2) % 1.0);
                    final dy = offset < 0.5
                        ? -3.5 * (offset / 0.5)
                        : -3.5 * (1 - (offset - 0.5) / 0.5);
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final String label;

  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: GlassContainer(
          blurSigma: context.mdGlassBlurSmall,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: context.mdGlassSurfaceStrong,
          borderColor: context.mdGlassBorder,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.mdSecondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String friendUserId;
  final String name;
  final String email;
  final ImageProvider<Object>? friendAvatarImage;
  final Future<void> Function(String postId)? onOpenForumPost;
  final Future<void> Function(_ChatMenuAction action)? onMenuAction;

  const _ChatHeader({
    required this.friendUserId,
    required this.name,
    required this.email,
    this.friendAvatarImage,
    this.onOpenForumPost,
    this.onMenuAction,
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
                  backgroundImage: friendAvatarImage,
                  child: friendAvatarImage == null
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
          const Spacer(),
          PopupMenuButton<_ChatMenuAction>(
            onSelected: (action) async {
              final handler = onMenuAction;
              if (handler != null) {
                await handler(action);
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: _ChatMenuAction.search,
                child: Text('Search messages'),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.clearChat,
                child: Text('Clear chat'),
              ),
            ],
            icon: Icon(Icons.more_vert, color: secondaryText),
          ),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;
  final bool sending;

  const _MessageComposer({
    required this.controller,
    required this.onSend,
    this.onChanged,
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
                onChanged: onChanged,
                minLines: 1,
                maxLines: 4,
                maxLength: _kMaxMessageLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                style: TextStyle(color: context.mdPrimaryText),
                decoration: InputDecoration(
                  hintText: 'Send some support...',
                  hintStyle: TextStyle(color: context.mdSecondaryText),
                  filled: true,
                  fillColor: context.mdInputFill,
                  counterText: '',
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
            SizedBox(
              width: 46,
              height: 46,
              child: GlassContainer(
                blurSigma: context.mdGlassBlurSmall,
                borderRadius: BorderRadius.circular(23),
                backgroundColor: sending
                    ? _kPurple.withValues(alpha: 0.44)
                    : _kPurple.withValues(alpha: 0.58),
                borderColor: context.mdGlassBorder,
                padding: EdgeInsets.zero,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(23),
                    onTap: sending ? null : onSend,
                    child: Center(
                      child: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
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
