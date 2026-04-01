import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/onboarding/onboarding_screen.dart';
import 'services/local_notifications_service.dart';
import 'services/push_notifications_service.dart';
import 'services/theme_controller.dart';
import 'utils/in_app_notifications.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  await LocalNotificationsService.instance.initialize();
  await PushNotificationsService.instance.initialize();
  InAppNotifications.instance.configure(_rootNavigatorKey);
  runApp(MoodiaryApp(themeController: ThemeController.instance));
}

class MoodiaryApp extends StatelessWidget {
  final ThemeController themeController;
  const MoodiaryApp({super.key, required this.themeController});

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
          home: const OnboardingScreen(),
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
