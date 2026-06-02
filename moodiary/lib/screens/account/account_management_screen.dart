import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/local_notifications_service.dart';
import '../../services/realtime_notifications.dart';
import '../../services/session_store.dart';
import '../../services/theme_controller.dart';
import '../../utils/transitions.dart';
import '../../utils/user_cache.dart';
import '../onboarding/onboarding_screen.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  String _userId = '';
  String _authToken = '';
  bool _isReady = false;
  bool _loadingSafetyLists = false;
  List<Map<String, dynamic>> _blockedUsers = const [];
  List<Map<String, dynamic>> _mutedUsers = const [];

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isChangingPassword = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    _userId = await SessionStore.instance.readUserId() ?? '';
    _authToken = await SessionStore.instance.readToken() ?? '';
    if (!mounted) return;
    setState(() => _isReady = true);
    await _loadSafetyLists();
  }

  Future<void> _loadSafetyLists() async {
    if (_userId.isEmpty || _authToken.isEmpty) return;
    setState(() => _loadingSafetyLists = true);
    try {
      final results = await Future.wait<dynamic>([
        AuthService.instance.getBlockedUsers(
          userId: _userId,
          authToken: _authToken,
        ),
        AuthService.instance.getMutedUsers(
          userId: _userId,
          authToken: _authToken,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _blockedUsers = (results[0] as List<Map<String, dynamic>>);
        _mutedUsers = (results[1] as List<Map<String, dynamic>>);
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Could not load blocked/muted users: $e');
    } finally {
      if (mounted) setState(() => _loadingSafetyLists = false);
    }
  }

  Future<void> _unblockUser(String targetUserId) async {
    if (!_isReady) return;
    try {
      await AuthService.instance.unblockUser(
        userId: _userId,
        authToken: _authToken,
        targetUserId: targetUserId,
      );
      await _loadSafetyLists();
      _showSuccess('User unblocked');
    } catch (e) {
      _showError('Could not unblock user: $e');
    }
  }

  Future<void> _unmuteUser(String targetUserId) async {
    if (!_isReady) return;
    try {
      await AuthService.instance.unmuteUser(
        userId: _userId,
        authToken: _authToken,
        targetUserId: targetUserId,
      );
      await _loadSafetyLists();
      _showSuccess('User unmuted');
    } catch (e) {
      _showError('Could not unmute user: $e');
    }
  }

  Future<void> _changePassword() async {
    // Validation
    if (_currentPasswordController.text.isEmpty) {
      _showError('Current password is required');
      return;
    }

    if (_newPasswordController.text.isEmpty) {
      _showError('New password is required');
      return;
    }

    if (_newPasswordController.text.length < 8) {
      _showError('Password must be at least 8 characters long');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await AuthService.instance.updateUserProfile(
        userId: _userId,
        authToken: _authToken,
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );

      if (mounted) {
        _showSuccess('Password changed successfully');
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This action cannot be undone. All your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) return;

    final password = await showDialog<String>(
      context: context,
      builder: (context) => _PasswordConfirmDialog(),
    );

    if (!mounted) return;
    if (password == null || password.isEmpty) return;

    try {
      await AuthService.instance.deleteAccount(
        userId: _userId,
        authToken: _authToken,
        password: password,
      );

      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        await UserCache.clear(prefs);
        await SessionStore.instance.clearSession();
        await prefs.remove('user_name');
        await prefs.remove('last_user_id');
        await prefs.remove('user_avatar_url');
        await prefs.remove('mbti_latest_type');
        RealtimeNotifications.instance.disconnect();
        await ThemeController.instance.resetToDefault();
        await LocalNotificationsService.instance.cancelAllScheduled();

        if (mounted) {
          unawaited(
            Navigator.of(context).pushAndRemoveUntil(
              FadeSlideRoute(page: const OnboardingScreen()),
              (_) => false,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error deleting account: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Management'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Change Password Section
            Text(
              'Change Password',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current Password
                    TextField(
                      controller: _currentPasswordController,
                      obscureText: !_showCurrentPassword,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        hintText: 'Enter your current password',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showCurrentPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _showCurrentPassword = !_showCurrentPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // New Password
                    TextField(
                      controller: _newPasswordController,
                      obscureText: !_showNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        hintText: 'Enter your new password (min 8 characters)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _showNewPassword = !_showNewPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirm Password
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: !_showConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        hintText: 'Re-enter your new password',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _showConfirmPassword = !_showConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Change Password Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isChangingPassword ? null : _changePassword,
                        child: _isChangingPassword
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Change Password'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            Text(
              'Safety Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Blocked Users',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _loadingSafetyLists
                              ? null
                              : _loadSafetyLists,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    if (_loadingSafetyLists)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      ),
                    if (_blockedUsers.isEmpty)
                      const Text('No blocked users.')
                    else
                      ..._blockedUsers.map(
                        (user) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text((user['name'] as String?) ?? 'User'),
                          subtitle: Text((user['email'] as String?) ?? ''),
                          trailing: TextButton(
                            onPressed: () => _unblockUser(
                              (user['_id'] ?? user['id']).toString(),
                            ),
                            child: const Text('Unblock'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Muted Users',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_mutedUsers.isEmpty)
                      const Text('No muted users.')
                    else
                      ..._mutedUsers.map(
                        (user) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text((user['name'] as String?) ?? 'User'),
                          subtitle: Text((user['email'] as String?) ?? ''),
                          trailing: TextButton(
                            onPressed: () => _unmuteUser(
                              (user['_id'] ?? user['id']).toString(),
                            ),
                            child: const Text('Unmute'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Danger Zone
            Text(
              'Danger Zone',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),

            // Delete Account
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Account',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Permanently delete your account and all associated data. This action cannot be undone.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _deleteAccount,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onError,
                        ),
                        child: const Text('Delete My Account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordConfirmDialog extends StatefulWidget {
  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _passwordController = TextEditingController();
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Password'),
      content: TextField(
        controller: _passwordController,
        obscureText: !_showPassword,
        decoration: InputDecoration(
          labelText: 'Enter your password to confirm',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _showPassword = !_showPassword;
              });
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _passwordController.text),
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
