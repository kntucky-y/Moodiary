// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:moodiary/main.dart';
import 'package:moodiary/screens/onboarding/onboarding_screen.dart';
import 'package:moodiary/services/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('renders onboarding screen by default', (tester) async {
    final controller = ThemeController.instance;
    await controller.load();

    await tester.pumpWidget(MoodiaryApp(themeController: controller));

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
