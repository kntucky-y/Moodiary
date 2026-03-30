import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_screen.dart';
import '../companion/companion_screen.dart';
import '../../utils/transitions.dart';

const _kPurple = Color(0xFF9B7FDB);
const _kDark = Color(0xFF1A1A2E);

// Change this to your machine's local IP when testing on a real device/emulator
// e.g. 'http://10.0.2.2:3000' for Android emulator, 'http://localhost:3000' for desktop
const _kBaseUrl = 'https://moodiary-production.up.railway.app';

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
      final endpoint = _isLogin ? '/api/auth/login' : '/api/auth/register';
      final body = _isLogin
          ? {'email': email, 'password': password}
          : {'email': email, 'password': password, 'name': name};

      final response = await http.post(
        Uri.parse('$_kBaseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user_name', data['user']['name']);
        final user = data['user'] as Map<String, dynamic>;
        final userId = (user['id'] ?? user['_id'])?.toString();
        if (userId != null && userId.isNotEmpty) {
          await prefs.setString('user_id', userId);
        }

        final companionId = prefs.getInt('companion_id');
        final companionName = prefs.getString('companion_name');

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            FadeSlideRoute(
              page: companionId != null && companionName != null
                  ? HomeScreen(
                      userName: data['user']['name'],
                      companionId: companionId,
                      companionName: companionName,
                    )
                  : CompanionScreen(userName: data['user']['name']),
            ),
            (_) => false,
          );
        }
      } else {
        _showError(data['error'] ?? 'Something went wrong');
      }
    } catch (e) {
      _showError('Cannot connect to server. Is the backend running?');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Beige curved top section
          Align(
            alignment: Alignment.topCenter,
            child: ClipPath(
              clipper: _TopCurveClipper(),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.28,
                color: const Color(0xFFF0E8DC),
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
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: _kDark,
                              ),
                              children: [
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
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: _kDark,
                              ),
                              children: [
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
                  const Text(
                    'Your Email',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _fieldDecoration('Enter your email'),
                  ),
                  const SizedBox(height: 24),
                  // Name field (signup only)
                  if (!_isLogin) ...[
                    const Text(
                      'Name',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: _fieldDecoration('Enter your name'),
                      controller: _nameController,
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Password label
                  if (_isLogin)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kDark,
                          ),
                        ),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF888888),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kDark,
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _isLogin
                        ? _obscurePassword
                        : _obscurePasswordSignup,
                    decoration:
                        _fieldDecoration(
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
                              color: const Color(0xFFAAAAAA),
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
                  // Divider
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or log in with',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // Social buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SocialButton(
                        color: const Color(0xFF1877F2),
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Facebook sign-in coming soon'),
                            duration: Duration(seconds: 2),
                          ),
                        ),
                        child: const Text(
                          'f',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      _SocialButton(
                        color: Colors.white,
                        border: true,
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Google sign-in coming soon'),
                            duration: Duration(seconds: 2),
                          ),
                        ),
                        child: const Text(
                          'G',
                          style: TextStyle(
                            color: Color(0xFF4285F4),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
                        style: const TextStyle(color: Color(0xFF888888)),
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

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFFDDDDDD)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _kPurple),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final Color color;
  final Widget child;
  final bool border;
  final VoidCallback? onTap;
  const _SocialButton({
    required this.color,
    required this.child,
    this.border = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: border ? Border.all(color: const Color(0xFFDDDDDD)) : null,
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(0, 0, 0, 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
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
