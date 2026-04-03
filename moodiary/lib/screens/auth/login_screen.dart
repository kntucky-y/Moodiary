import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/push_notifications_service.dart';
import '../../services/realtime_notifications.dart';
import '../../theme/moodiary_colors.dart';
import '../../utils/transitions.dart';
import '../../utils/user_cache.dart';
import '../companion/companion_screen.dart';
import '../home/home_screen.dart';
import 'reset_password_screen.dart';

const _kPurple = Color(0xFF9B7FDB);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLogin = true;
  bool _obscurePasswordSignup = true;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _finalizeLogin(Map<String, dynamic> data) async {
    final token = data['token'] as String?;
    final user = (data['user'] as Map<String, dynamic>?) ?? {};

    if (token == null) {
      throw AuthException('Invalid response from server');
    }

    final prefs = await SharedPreferences.getInstance();
    final lastUserId = prefs.getString('last_user_id');
    await prefs.setString('token', token);

    final userName = (user['name'] ?? 'Friend') as String;
    await prefs.setString('user_name', userName);
    final avatarUrl = (user['avatarUrl'] as String?)?.trim();
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      await prefs.setString('user_avatar_url', avatarUrl);
    } else {
      await prefs.remove('user_avatar_url');
    }

    final userId = (user['id'] ?? user['_id'])?.toString();
    if (userId != null && userId.isNotEmpty) {
      if (lastUserId != null && lastUserId != userId) {
        await UserCache.clear(prefs);
      }
      await prefs.setString('user_id', userId);
      await prefs.setString('last_user_id', userId);
    }

    await RealtimeNotifications.instance.ensureConnected(token: token);
    await PushNotificationsService.instance.syncWithAuthToken(token);

    unawaited(_warmProfileCache(userId: userId, authToken: token));

    final companionId = prefs.getInt('companion_id');
    final companionName = prefs.getString('companion_name');

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      FadeSlideRoute(
        page: companionId != null && companionName != null
            ? HomeScreen(
                userName: userName,
                companionId: companionId,
                companionName: companionName,
              )
            : CompanionScreen(userName: userName),
      ),
      (_) => false,
    );
  }

  Future<void> _warmProfileCache({
    required String? userId,
    required String authToken,
  }) async {
    if (userId == null || userId.isEmpty) return;

    try {
      final results = await Future.wait<dynamic>([
        AuthService.instance.getUserProfile(userId: userId),
        AuthService.instance.getMyForumPosts(authToken: authToken),
      ]);
      final bundle = {
        'profile': results[0] as Map<String, dynamic>,
        'posts': results[1] as List<Map<String, dynamic>>,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UserCache.profileBundleCacheKey,
        jsonEncode(bundle),
      );
    } catch (_) {
      // Cache warm-up is best-effort only.
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final data = _isLogin
          ? await AuthService.instance.login(email: email, password: password)
          : await AuthService.instance.register(
              name: name,
              email: email,
              password: password,
            );

      await _finalizeLogin(data);
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Cannot connect to the server right now');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showForgotPasswordSheet() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (sheetContext, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Forgot password',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'you@example.com',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final email = controller.text.trim();
                              if (email.isEmpty) {
                                _showError('Please enter your email');
                                return;
                              }

                              setModalState(() => isSubmitting = true);

                              try {
                                final message = await AuthService.instance
                                    .requestPasswordReset(email: email);
                                if (!mounted) return;
                                Navigator.of(context).pop();
                                _showInfo(message);
                              } on AuthException catch (error) {
                                setModalState(() => isSubmitting = false);
                                _showError(error.message);
                              } catch (_) {
                                setModalState(() => isSubmitting = false);
                                _showError(
                                  'Unable to send reset email right now',
                                );
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send reset link'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ResetPasswordScreen(),
                        ),
                      );
                    },
                    child: const Text('Already have a reset token?'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryText = context.mdPrimaryText;
    final subtleText = context.mdSecondaryText;

    return Scaffold(
      backgroundColor: context.mdScaffold,
      body: Stack(
        children: [
          // Beige curved top section
          Align(
            alignment: Alignment.topCenter,
            child: ClipPath(
              clipper: _TopCurveClipper(),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.28,
                color: context.mdSecondarySurface,
              ),
            ),
          ),
          // Scrollable content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 72),
                  // Title
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isLogin
                        ? RichText(
                            key: const ValueKey('login-title'),
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                              children: const [
                                TextSpan(text: 'Log '),
                                TextSpan(
                                  text: 'I',
                                  style: TextStyle(color: Color(0xFF4A90D9)),
                                ),
                                TextSpan(text: 'n'),
                              ],
                            ),
                          )
                        : RichText(
                            key: const ValueKey('signup-title'),
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: primaryText,
                              ),
                              children: const [
                                TextSpan(text: 'Sign '),
                                TextSpan(
                                  text: 'U',
                                  style: TextStyle(color: Color(0xFF5DB87A)),
                                ),
                                TextSpan(text: 'p'),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 36),
                  // Email field (shared)
                  Text(
                    'Your Email',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: primaryText),
                    decoration: _fieldDecoration(context, 'Enter your email'),
                  ),
                  const SizedBox(height: 24),
                  // Name field (signup only)
                  if (!_isLogin) ...[
                    Text(
                      'Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      style: TextStyle(color: primaryText),
                      decoration: _fieldDecoration(context, 'Enter your name'),
                      controller: _nameController,
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Password label
                  if (_isLogin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primaryText,
                          ),
                        ),
                        TextButton(
                          onPressed: _showForgotPasswordSheet,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Forgot password?',
                            style: TextStyle(fontSize: 13, color: subtleText),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryText,
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    style: TextStyle(color: primaryText),
                    obscureText: _isLogin
                        ? _obscurePassword
                        : _obscurePasswordSignup,
                    decoration:
                        _fieldDecoration(
                          context,
                          _isLogin
                              ? 'Enter your password'
                              : 'Create a password',
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              (_isLogin
                                      ? _obscurePassword
                                      : _obscurePasswordSignup)
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: subtleText,
                              size: 20,
                            ),
                            onPressed: () => setState(() {
                              if (_isLogin) {
                                _obscurePassword = !_obscurePassword;
                              } else {
                                _obscurePasswordSignup =
                                    !_obscurePasswordSignup;
                              }
                            }),
                          ),
                        ),
                  ),
                  const SizedBox(height: 36),
                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2C2C2C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              _isLogin ? 'Log in' : 'Sign up',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLogin
                            ? "Don't have an account?  "
                            : 'Already have an account?  ',
                        style: TextStyle(color: subtleText),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                          _isLogin ? 'Sign up' : 'Log in',
                          style: const TextStyle(
                            color: _kPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          // Back button — must be last in Stack to receive touches
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios,
                color: Color(0xFF888888),
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: context.mdSecondaryText),
      filled: true,
      fillColor: context.mdInputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: context.mdInputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: context.mdAccentPurple, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: context.mdInputBorder),
      ),
    );
  }
}

class _TopCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.72);
    path.quadraticBezierTo(
      size.width * 0.5,
      size.height * 1.12,
      size.width,
      size.height * 0.72,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TopCurveClipper old) => false;
}
