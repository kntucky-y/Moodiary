import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _kBaseUrl = 'https://moodiary-production.up.railway.app';
const _kPurple = Color(0xFFA076F9);
const _kBubbleMine = Color(0xFF4338CA);
const _kBubbleFriend = Color(0xFFF1F5F9);

class FriendChatScreen extends StatefulWidget {
  final String friendshipId;
  final String friendName;
  final String friendEmail;

  const FriendChatScreen({
    super.key,
    required this.friendshipId,
    required this.friendName,
    required this.friendEmail,
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
  io.Socket? _socket;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _userId = prefs.getString('user_id');
    await _loadHistory();
    _connectSocket();
  }

  Future<void> _loadHistory() async {
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final resp = await http.get(
        Uri.parse('$_kBaseUrl/api/friends/${widget.friendshipId}/messages'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        setState(() {
          _messages
            ..clear()
            ..addAll(
              data.map(
                (j) => _FriendMessage.fromJson(
                  j as Map<String, dynamic>,
                  _userId,
                ),
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
            final pendingIndex = _messages.lastIndexWhere(
              (m) =>
                  m.pending &&
                  m.text == incoming.text &&
                  incoming.isMine &&
                  (incoming.createdAt.difference(m.createdAt).abs() <
                      const Duration(seconds: 3)),
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
      if (_socket != null && _socket!.connected) {
        _socket!.emit(
          'friends:message',
          {'friendshipId': widget.friendshipId, 'text': text},
        );
      } else {
        await http.post(
          Uri.parse('$_kBaseUrl/api/friends/${widget.friendshipId}/messages'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'text': text}),
        );
        await _loadHistory();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E8FF),
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(name: widget.friendName, email: widget.friendEmail),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
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
                              return _ChatBubble(message: message);
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

  factory _FriendMessage.fromJson(
    Map<String, dynamic> json,
    String? viewerId,
  ) {
    final createdRaw = json['createdAt'];
    final createdAt = createdRaw is String
        ? DateTime.parse(createdRaw).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(createdRaw as int).toLocal();
    final sender = json['sender']?.toString();
    return _FriendMessage(
      id: json['id'].toString(),
      text: json['text'] as String,
      createdAt: createdAt,
      isMine: sender != null && sender == viewerId,
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _FriendMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final alignment = message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor = message.isMine ? _kBubbleMine : _kBubbleFriend;
    final textColor = message.isMine ? Colors.white : const Color(0xFF111827);

    return Align(
      alignment: alignment,
      child: Container(
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
          crossAxisAlignment:
              message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
            if (message.pending)
              const Text(
                'sending...',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
          ],
        ),
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
  final String name;
  final String email;

  const _ChatHeader({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _kPurple),
          ),
          const SizedBox(width: 12),
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
                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
            ],
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: const BoxDecoration(color: Colors.white),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Send some support...',
                  filled: true,
                  fillColor: const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: sending ? null : onSend,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: sending ? _kPurple.withOpacity(0.5) : _kPurple,
                  shape: BoxShape.circle,
                ),
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
          const Text(
            'Offer a little encouragement today.',
            style: TextStyle(color: Color(0xFF888888)),
          ),
        ],
      ),
    );
  }
}
*** End File