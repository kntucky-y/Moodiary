import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/companion/companion_screen.dart';
import 'screens/profile/mbti_test_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/app_shell.dart';
import 'services/auth_service.dart';
import 'services/local_notifications_service.dart';
import 'services/push_notifications_service.dart';
import 'services/realtime_notifications.dart';
import 'services/theme_controller.dart';
import 'utils/transitions.dart';
import 'utils/in_app_notifications.dart';
import 'utils/user_cache.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

(bool, String?) _resolveStartupResetRoute(Uri uri) {
  final candidates = <Uri>[uri];

  final fragment = uri.fragment.trim();
  if (fragment.isNotEmpty) {
    final normalizedFragment = fragment.startsWith('/')
        ? fragment.substring(1)
        : fragment;
    final fragmentUri = Uri.tryParse(normalizedFragment);
    if (fragmentUri != null) {
      candidates.add(fragmentUri);
    }
  }

  for (final candidate in candidates) {
    final token = candidate.queryParameters['token'];
    final routePath = candidate.path.toLowerCase();
    final hasResetRoute = routePath.contains('reset-password');
    if ((token != null && token.isNotEmpty) || hasResetRoute) {
      return (true, token);
    }
  }

  return (false, null);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await DataSaverMode.load();
  await LocalNotificationsService.instance.initialize();
  await PushNotificationsService.instance.initialize();
  InAppNotifications.instance.configure(_rootNavigatorKey);
  final startupRoute = _resolveStartupResetRoute(Uri.base);
  runApp(
    MoodiaryApp(
      themeController: ThemeController.instance,
      showResetPasswordScreen: startupRoute.$1,
      initialResetToken: startupRoute.$2,
    ),
  );
}

class MoodiaryApp extends StatelessWidget {
  final ThemeController themeController;
  final bool showResetPasswordScreen;
  final String? initialResetToken;

  const MoodiaryApp({
    super.key,
    required this.themeController,
    required this.showResetPasswordScreen,
    required this.initialResetToken,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController.listenable,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: _rootNavigatorKey,
          title: 'Moodiary',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          home: showResetPasswordScreen
              ? ResetPasswordScreen(initialToken: initialResetToken)
              : const StartupGate(),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B7FDB)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      useMaterial3: true,
      textTheme: GoogleFonts.lexendTextTheme(),
    );
  }

  ThemeData _buildDarkTheme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9B7FDB),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F1119),
      cardColor: const Color(0xFF1B1E2C),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<Widget> _startupFuture;

  @override
  void initState() {
    super.initState();
    _startupFuture = _resolveStartupScreen();
  }

  Future<Widget> _resolveStartupScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token')?.trim() ?? '';

    if (token.isEmpty) {
      return const OnboardingScreen();
    }

    try {
      await AuthService.instance.getConnectedUserIds(authToken: token);
      await RealtimeNotifications.instance.ensureConnected(token: token);
    } catch (_) {
      await _clearStoredSession(prefs);
      return const OnboardingScreen();
    }

    final userName = prefs.getString('user_name')?.trim();
    final mbtiLatestType = prefs.getString('mbti_latest_type')?.trim();
    final companionId = prefs.getInt('companion_id');
    final companionName = prefs.getString('companion_name')?.trim();

    final resolvedUserName = userName == null || userName.isEmpty
        ? 'Friend'
        : userName;
    final hasMbti = mbtiLatestType != null && mbtiLatestType.isNotEmpty;
    final hasCompanion =
        companionId != null &&
        companionName != null &&
        companionName.isNotEmpty;

    if (!hasMbti) {
      return MbtiTestScreen(
        userName: resolvedUserName,
        requireCompanionSelection: !hasCompanion,
        forceHomeOnComplete: hasCompanion,
        initialCompanionId: companionId,
        initialCompanionName: companionName,
      );
    }

    if (!hasCompanion) {
      return CompanionScreen(userName: resolvedUserName);
    }

    return MoodiaryShell(
      userName: resolvedUserName,
      companionId: companionId,
      companionName: companionName,
      initialTab: MoodiaryTab.home,
    );
  }

  Future<void> _clearStoredSession(SharedPreferences prefs) async {
    await prefs.remove('token');
    await prefs.remove('user_name');
    await prefs.remove('user_id');
    await prefs.remove('last_user_id');
    await prefs.remove('user_avatar_url');
    await prefs.remove('mbti_latest_type');
    RealtimeNotifications.instance.disconnect();
    await UserCache.clear(prefs);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Unable to restore your session.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please log in again.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          FadeSlideRoute(page: const LoginScreen()),
                        );
                      },
                      child: const Text('Go to login'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return snapshot.data ?? const OnboardingScreen();
      },
    );
  }
}
