import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/auth/reset_password_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/local_notifications_service.dart';
import 'services/push_notifications_service.dart';
import 'services/theme_controller.dart';
import 'utils/transitions.dart';
import 'utils/in_app_notifications.dart';

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
              : const OnboardingScreen(),
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
