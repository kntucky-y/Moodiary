import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../utils/transitions.dart';
import '../../utils/avatar_utils.dart';
import '../forums/forums_screen.dart';
import '../../widgets/user_profile_popup.dart';

class UserDiscoveryScreen extends StatefulWidget {
  const UserDiscoveryScreen({super.key});

  @override
  State<UserDiscoveryScreen> createState() => _UserDiscoveryScreenState();
}

class _UserDiscoveryScreenState extends State<UserDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _authToken = '';
  String _userName = '';
  int _companionId = 1;
  String _companionName = 'Companion';
  bool _loading = false;
  bool _hasSearched = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _init();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString('token') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _companionId = prefs.getInt('companion_id') ?? 1;
    _companionName = prefs.getString('companion_name') ?? 'Companion';
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(_searchController.text.trim());
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    if (query.length < 2) {
      setState(() {
        _hasSearched = false;
        _results = [];
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _hasSearched = true;
    });

    try {
      final results = await AuthService.instance.searchUsers(
        query: query,
        authToken: _authToken,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest(String email) async {
    try {
      await AuthService.instance.sendFriendRequest(
        authToken: _authToken,
        email: email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start request: $e')));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Friends'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _hasSearched = false;
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onSubmitted: _search,
            ),
          ),
          Expanded(
            child: _hasSearched && _results.isEmpty && !_loading
                ? const Center(child: Text('No users found.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      final userId = user['id']?.toString() ?? '';
                      final email = user['email']?.toString() ?? '';
                      final name = user['name']?.toString() ?? 'User';
                      final bio = user['bio']?.toString() ?? '';
                      final avatarUrl = user['avatarUrl'] as String?;

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarImageProvider(avatarUrl),
                            child: avatarImageProvider(avatarUrl) == null
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                  )
                                : null,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            bio.isNotEmpty ? bio : email,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: userId.isEmpty
                              ? null
                              : () async {
                                  final selectedPostId =
                                      await showUserProfilePopup(
                                        context,
                                        userId: userId,
                                      );
                                  if (selectedPostId == null || !mounted) {
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    FadeSlideRoute(
                                      page: ForumsScreen(
                                        userName: _userName,
                                        companionId: _companionId,
                                        companionName: _companionName,
                                        initialPostId: selectedPostId,
                                      ),
                                    ),
                                  );
                                },
                          trailing: TextButton(
                            onPressed: email.isEmpty
                                ? null
                                : () => _sendFriendRequest(email),
                            child: const Text('Request'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
