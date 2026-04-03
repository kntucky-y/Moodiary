import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<Map<String, dynamic>> _profileFuture;
  late String _userId;
  late String _authToken;
  bool _isEditing = false;

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('userId') ?? '';
    _authToken = prefs.getString('token') ?? '';

    setState(() {
      _profileFuture = AuthService.instance.getUserProfile(userId: _userId);
    });
  }

  Future<void> _saveProfile() async {
    try {
      await AuthService.instance.updateUserProfile(
        userId: _userId,
        authToken: _authToken,
        name: _nameController.text,
        email: _emailController.text,
        bio: _bioController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        setState(() {
          _isEditing = false;
          _profileFuture = AuthService.instance.getUserProfile(userId: _userId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                });
              },
            ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
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

          final userData = snapshot.data?['user'] as Map<String, dynamic>?;
          if (userData == null) {
            return const Center(child: Text('Profile not found'));
          }

          // Initialize form fields on first load
          if (!_isEditing &&
              _nameController.text.isEmpty &&
              userData['name'] != null) {
            _nameController.text = userData['name'] as String;
            _emailController.text = userData['email'] as String? ?? '';
            _bioController.text = userData['bio'] as String? ?? '';
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar section
                Center(
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: userData['avatarUrl'] != null
                        ? NetworkImage(userData['avatarUrl'] as String)
                        : null,
                    child: userData['avatarUrl'] == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                ),
                const SizedBox(height: 24),

                // Name
                Text('Name', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_isEditing)
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Your name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(userData['name'] as String? ?? 'N/A'),
                    ),
                  ),
                const SizedBox(height: 20),

                // Email
                Text('Email', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_isEditing)
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'your.email@example.com',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(userData['email'] as String? ?? 'N/A'),
                    ),
                  ),
                const SizedBox(height: 20),

                // Bio
                Text('Bio', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_isEditing)
                  TextField(
                    controller: _bioController,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Tell us about yourself...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        userData['bio'] as String? ?? 'No bio',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Member since
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Member Since',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              userData['createdAt'] != null
                                  ? DateTime.parse(
                                      userData['createdAt'] as String,
                                    ).toString().split(' ')[0]
                                  : 'N/A',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Save button (only when editing)
                if (_isEditing)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
