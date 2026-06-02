import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/app_shell.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/companion/companion_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/mbti_test_screen.dart';
import 'services/auth_service.dart';
import 'services/local_notifications_service.dart';
import 'services/push_notifications_service.dart';
import 'services/realtime_notifications.dart';
import 'services/session_store.dart';
import 'services/theme_controller.dart';
import 'theme/moodiary_colors.dart';
import 'utils/in_app_notifications.dart';
import 'utils/route_observer.dart';
import 'utils/transitions.dart';
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
          navigatorObservers: [routeObserver],
          themeMode: mode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          builder: (context, child) => _AdaptiveAppFrame(child: child),
          home: showResetPasswordScreen
              ? ResetPasswordScreen(initialToken: initialResetToken)
              : const StartupGate(),
        );
      },
    );
  }

  ThemeData _buildLightTheme() {
    const primaryText = Color(0xFF1A1A2E);
    const secondaryText = Color(0xFF8A8A8D);
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF9B7FDB)),
      scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      useMaterial3: true,
      textTheme: GoogleFonts.lexendTextTheme().apply(
        bodyColor: primaryText,
        displayColor: primaryText,
      ),
    );
    return base.copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: secondaryText),
        labelStyle: TextStyle(color: secondaryText),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: base.colorScheme.primary,
        selectionColor: base.colorScheme.primary.withValues(alpha: 0.22),
        selectionHandleColor: base.colorScheme.primary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.62),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.42)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: base.colorScheme.surface.withValues(alpha: 0.84),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.68),
        indicatorColor: base.colorScheme.primaryContainer.withValues(
          alpha: 0.75,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _glassButtonStyle(isDark: false),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _glassButtonStyle(isDark: false),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _glassButtonStyle(isDark: false, outlined: true),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _glassTextButtonStyle(isDark: false),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const primaryText = Colors.white;
    final secondaryText = Colors.white.withValues(alpha: 0.75);
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9B7FDB),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(bodyColor: primaryText, displayColor: primaryText),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F1119),
      cardColor: const Color(0xFF1B1E2C),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: secondaryText),
        labelStyle: TextStyle(color: secondaryText),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: base.colorScheme.primary,
        selectionColor: base.colorScheme.primary.withValues(alpha: 0.32),
        selectionHandleColor: base.colorScheme.primary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.1),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: const Color(0xFF1B1F2C).withValues(alpha: 0.82),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1B1F2C).withValues(alpha: 0.66),
        indicatorColor: base.colorScheme.primaryContainer.withValues(
          alpha: 0.62,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _glassButtonStyle(isDark: true),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _glassButtonStyle(isDark: true),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _glassButtonStyle(isDark: true, outlined: true),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _glassTextButtonStyle(isDark: true),
      ),
    );
  }

  ButtonStyle _glassButtonStyle({required bool isDark, bool outlined = false}) {
    final defaultBg = isDark
        ? Colors.white.withValues(alpha: outlined ? 0.0 : 0.16)
        : Colors.white.withValues(alpha: outlined ? 0.0 : 0.56);
    final pressedBg = isDark
        ? Colors.white.withValues(alpha: outlined ? 0.12 : 0.24)
        : Colors.white.withValues(alpha: outlined ? 0.22 : 0.68);
    final disabledBg = isDark
        ? Colors.white.withValues(alpha: outlined ? 0.04 : 0.08)
        : Colors.white.withValues(alpha: outlined ? 0.08 : 0.32);
    final foreground = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final disabledFg = foreground.withValues(alpha: 0.42);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.46);

    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledBg;
        if (states.contains(WidgetState.pressed)) return pressedBg;
        return defaultBg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return disabledFg;
        return foreground;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (!outlined) {
          return BorderSide(color: border);
        }
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: border.withValues(alpha: 0.4));
        }
        if (states.contains(WidgetState.pressed)) {
          return BorderSide(color: border.withValues(alpha: 0.95));
        }
        return BorderSide(color: border);
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      overlayColor: WidgetStatePropertyAll(
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
    );
  }

  ButtonStyle _glassTextButtonStyle({required bool isDark}) {
    final fg = isDark ? Colors.white : const Color(0xFF2A2144);
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return fg.withValues(alpha: 0.42);
        }
        return fg;
      }),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w600),
      ),
      overlayColor: WidgetStatePropertyAll(
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
      ),
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
    final token = (await SessionStore.instance.readToken())?.trim() ?? '';

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
    await SessionStore.instance.clearSession();
    await prefs.remove('user_name');
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
          return Scaffold(
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    context.mdScaffold,
                    context.mdSecondarySurface.withValues(alpha: 0.55),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
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

class _AdaptiveAppFrame extends StatelessWidget {
  final Widget? child;

  const _AdaptiveAppFrame({required this.child});

  double _resolveMaxWidth(double width) {
    if (width >= 1400) return 900;
    if (width >= 1000) return 820;
    if (width >= 700) return 720;
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final content = child;
    if (content == null) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final maxWidth = _resolveMaxWidth(width);
    final sideInset = width >= 1000
        ? 24.0
        : width >= 700
        ? 16.0
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.mdScaffold,
            context.mdSecondarySurface.withValues(alpha: 0.28),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sideInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        ),
      ),
    );
  }
}
