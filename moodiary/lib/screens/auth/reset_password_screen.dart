import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail, this.initialToken});

  final String? initialEmail;
  final String? initialToken;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  final List<TextEditingController> _codeControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _codeFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isSubmitting = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isOtpComplete = false;
  bool _isEmailLocked = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialEmail ?? '').isNotEmpty) {
      _emailController.text = widget.initialEmail!;
      _isEmailLocked = true;
    }
    if ((widget.initialToken ?? '').isNotEmpty) {
      _applyToken(widget.initialToken!);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _passwordFocusNode.dispose();
    for (final controller in _codeControllers) {
      controller.dispose();
    }
    for (final node in _codeFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String _currentCode() {
    return _codeControllers.map((controller) => controller.text).join();
  }

  void _applyToken(String token) {
    final trimmed = token.trim();
    if (trimmed.length != 6) return;

    for (var i = 0; i < 6; i++) {
      _codeControllers[i].text = trimmed[i];
    }

    _updateOtpState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _passwordFocusNode.requestFocus();
      }
    });
  }

  void _updateOtpState() {
    final isComplete = _codeControllers.every(
      (controller) => controller.text.trim().isNotEmpty,
    );
    if (_isOtpComplete != isComplete) {
      setState(() => _isOtpComplete = isComplete);
    }
  }

  void _handleCodeInput(int index, String value) {
    if (value.length > 1) {
      final chars = value.replaceAll(RegExp(r'\D'), '').split('');
      if (chars.isEmpty) return;

      var fillIndex = index;
      for (final char in chars) {
        if (fillIndex >= _codeControllers.length) break;
        _codeControllers[fillIndex].text = char;
        fillIndex += 1;
      }

      if (fillIndex < _codeFocusNodes.length) {
        _codeFocusNodes[fillIndex].requestFocus();
      } else {
        _passwordFocusNode.requestFocus();
      }
      _updateOtpState();
      return;
    }

    if (value.isNotEmpty && index < _codeFocusNodes.length - 1) {
      _codeFocusNodes[index + 1].requestFocus();
    }

    if (value.isNotEmpty && index == _codeFocusNodes.length - 1) {
      _passwordFocusNode.requestFocus();
    }

    if (value.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
    }

    _updateOtpState();
  }

  Future<void> _handleReset() async {
    final email = _emailController.text.trim();
    final token = _currentCode().trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (token.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    if (token.length != 6) {
      _showSnack('Enter the 6-digit verification code');
      return;
    }

    if (token.length == 6 && email.isEmpty) {
      _showSnack('Email is required for the verification code flow');
      return;
    }

    if (password != confirm) {
      _showSnack('Passwords do not match');
      return;
    }

    if (password.length < 8) {
      _showSnack('Password must be at least 8 characters long');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthService.instance.resetPassword(
        email: email.isEmpty ? null : email,
        token: token,
        password: password,
      );
      if (!mounted) return;
      _showSnack('Password updated successfully');
      Navigator.of(context).pop();
    } on AuthException catch (err) {
      _showSnack(err.message);
    } catch (_) {
      _showSnack('Unable to reset password right now');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                readOnly: _isEmailLocked,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: 'Use the same email that received the code',
                ),
              ),
              const SizedBox(height: 24),
              Text('Verification code', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                'Enter the 6-digit code from your email',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) => SizedBox(
                    width: 48,
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.backspace) {
                          if (_codeControllers[index].text.isEmpty &&
                              index > 0) {
                            _codeFocusNodes[index - 1].requestFocus();
                            _codeControllers[index - 1]
                                .selection = TextSelection.collapsed(
                              offset: _codeControllers[index - 1].text.length,
                            );
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _codeControllers[index],
                        focusNode: _codeFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 1,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                        onChanged: (value) => _handleCodeInput(index, value),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isOtpComplete
                    ? Column(
                        key: const ValueKey('password-fields'),
                        children: [
                          TextField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            obscureText: _obscureNewPassword,
                            decoration: InputDecoration(
                              labelText: 'New password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureNewPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscureNewPassword =
                                      !_obscureNewPassword,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _confirmController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              labelText: 'Confirm password',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirmPassword =
                                      !_obscureConfirmPassword,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting || !_isOtpComplete
                      ? null
                      : _handleReset,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
