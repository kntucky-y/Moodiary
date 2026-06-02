// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moodiary/main.dart';
import 'package:moodiary/screens/onboarding/onboarding_screen.dart';
import 'package:moodiary/services/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('renders onboarding screen by default', (tester) async {
    final controller = ThemeController.instance;
    await controller.load();

    await tester.pumpWidget(
      MoodiaryApp(
        themeController: controller,
        showResetPasswordScreen: false,
        initialResetToken: null,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
