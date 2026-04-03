import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _pageSize = 20;

  String _authToken = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _showUnreadOnly = false;
  bool _hasMore = true;
  int _offset = 0;
  int _unreadCount = 0;
  final List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token') ?? '';
    await _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_authToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
      });
      return;
    }

    if (reset) {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final response = await AuthService.instance.getNotifications(
        authToken: _authToken,
        limit: _pageSize,
        offset: reset ? 0 : _offset,
        unreadOnly: _showUnreadOnly,
      );

      final incoming = response['items'] as List<Map<String, dynamic>>;
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(incoming);
        } else {
          _items.addAll(incoming);
        }
        _offset = (reset ? 0 : _offset) + incoming.length;
        _hasMore = response['hasMore'] as bool? ?? false;
        _unreadCount = response['unreadCount'] as int? ?? 0;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load notifications: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await AuthService.instance.markNotificationRead(
        authToken: _authToken,
        notificationId: id,
      );
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not mark as read: $e')));
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await AuthService.instance.markAllNotificationsRead(
        authToken: _authToken,
      );
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not mark all as read: $e')));
    }
  }

  Future<void> _deleteItem(String id) async {
    try {
      await AuthService.instance.deleteNotification(
        authToken: _authToken,
        notificationId: id,
      );
      setState(() {
        _items.removeWhere((item) => item['id'] == id);
      });
      await _load(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete notification: $e')),
      );
    }
  }

  String _subtitle(Map<String, dynamic> item) {
    final payload = item['payload'] as Map<String, dynamic>? ?? const {};
    final text = payload['text']?.toString();
    final message = payload['message']?.toString();
    final from = payload['from'] as Map<String, dynamic>?;
    final fromName = from?['name']?.toString();

    if (text != null && text.isNotEmpty) {
      return fromName != null ? '$fromName: $text' : text;
    }
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return item['type']?.toString() ?? 'Notification';
  }

  String _title(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? 'notification';
    switch (type) {
      case 'friend_message':
        return 'New message';
      case 'friend_removed':
        return 'Friendship update';
      case 'friend_request':
        return 'Friend request';
      default:
        return 'Notification';
    }
  }

  IconData _icon(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? 'notification';
    switch (type) {
      case 'friend_message':
        return Icons.chat_bubble_outline;
      case 'friend_removed':
        return Icons.person_remove_alt_1_outlined;
      case 'friend_request':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications ($_unreadCount unread)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Mark all as read',
            onPressed: _items.isEmpty ? null : _markAllAsRead,
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile.adaptive(
            title: const Text('Show unread only'),
            value: _showUnreadOnly,
            onChanged: (value) {
              setState(() => _showUnreadOnly = value);
              _load(reset: true);
            },
          ),
          const Divider(height: 0),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? const Center(child: Text('No notifications yet.'))
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                          notification.metrics.maxScrollExtent - 120) {
                        _load(reset: false);
                      }
                      return false;
                    },
                    child: ListView.separated(
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, index) => const Divider(height: 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final item = _items[index];
                        final id = item['id']?.toString() ?? '';
                        final isRead = item['isRead'] as bool? ?? false;
                        final createdAt = DateTime.tryParse(
                          item['createdAt']?.toString() ?? '',
                        );

                        return Dismissible(
                          key: ValueKey('notif-$id'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.redAccent,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => _deleteItem(id),
                          child: ListTile(
                            leading: Icon(_icon(item)),
                            title: Text(
                              _title(item),
                              style: TextStyle(
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              _subtitle(item),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (createdAt != null)
                                  Text(
                                    '${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (!isRead)
                                  TextButton(
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => _markAsRead(id),
                                    child: const Text('Mark read'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
