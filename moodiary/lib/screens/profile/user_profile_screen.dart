import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../utils/avatar_utils.dart';

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
  String? _selectedAvatarDataUrl;
  String? _currentAvatarUrl;

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
    _userId = prefs.getString('user_id') ?? prefs.getString('userId') ?? '';
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
        avatarUrl: _selectedAvatarDataUrl,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _nameController.text.trim());
      if (_selectedAvatarDataUrl != null &&
          _selectedAvatarDataUrl!.isNotEmpty) {
        await prefs.setString('user_avatar_url', _selectedAvatarDataUrl!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        setState(() {
          _isEditing = false;
          _selectedAvatarDataUrl = null;
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

  Future<void> _pickAvatarImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 768,
      maxHeight: 768,
    );
    if (picked == null) return;

    final Uint8List bytes = await picked.readAsBytes();
    final lower = picked.path.toLowerCase();
    final mimeType = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final dataUrl = dataUrlFromImageBytes(bytes, mimeType: mimeType);

    if (dataUrl == null) return;
    if (!mounted) return;
    setState(() {
      _selectedAvatarDataUrl = dataUrl;
    });
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

          _currentAvatarUrl = userData['avatarUrl'] as String?;
          final displayedAvatarUrl =
              _selectedAvatarDataUrl ?? _currentAvatarUrl;

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
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: avatarImageProvider(
                          displayedAvatarUrl,
                        ),
                        child: avatarImageProvider(displayedAvatarUrl) == null
                            ? const Icon(Icons.person, size: 50)
                            : null,
                      ),
                      if (_isEditing) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickAvatarImage,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Upload profile photo'),
                        ),
                      ],
                    ],
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
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText:
                          'Tell us about yourself... Emojis are welcome 😊',
                      helperText: 'You can use emojis in your bio.',
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
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
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
