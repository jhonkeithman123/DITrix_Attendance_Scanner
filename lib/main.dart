import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/capture_id_screen.dart';
import 'screens/about_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/shared_capture_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize the Application
  final prefs = await SharedPreferences.getInstance();
  final showOnboarding = !(prefs.getBool('onboarding_done') ?? false);
  await ThemeController.instance.load();
  runApp(StudentIdScannerApp(showOnboarding: showOnboarding));
}

class StudentIdScannerApp extends StatelessWidget {
  const StudentIdScannerApp({super.key, required this.showOnboarding});
  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: Colors.green.shade700,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: Colors.green.shade900,
      brightness: Brightness.dark,
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'DITrix Attendance Scanner',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: lightScheme,
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor:
                lightScheme.onSurface, // dark text/icons in light mode
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: darkScheme,
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor:
                darkScheme.onSurface, // light text/icons in dark mode (auto)
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
          child: child ?? const SizedBox.shrink(),
        ),
        routes: {
          '/home': (_) => const HomeScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignupScreen(),
          '/forgot': (_) => const ForgotPasswordScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/about': (_) => const AboutScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/tutorial': (_) => const TutorialScreen(),
        },
        onGenerateRoute: (settings) {
          // Handle routes with parameters
          if (settings.name == '/capture') {
            final args = settings.arguments as Map<String, dynamic>?;
            final sessionId = args?['sessionId'] as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => CaptureIdScreen(sessionId: sessionId),
              settings: settings,
            );
          }
          if (settings.name == '/verify') {
            final args = settings.arguments as Map<String, dynamic>?;
            final email = args?['email'] as String? ?? '';
            final notice = args?['notice'];
            return MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(email: email, notice: notice),
              settings: settings,
            );
          }
          if (settings.name == '/reset') {
            final args = settings.arguments as Map<String, dynamic>?;
            final email = args?['email'] as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => ResetPasswordScreen(email: email),
              settings: settings,
            );
          }
          if (settings.name == '/shared-capture') {
            final args = settings.arguments as Map<String, dynamic>?;
            final captureId = args?['captureId'] as String? ?? '';
            return MaterialPageRoute(
              builder: (_) => SharedCaptureScreen(captureId: captureId),
              settings: settings,
            );
          }
          return null;
        },
        initialRoute: showOnboarding ? '/onboarding' : '/home',
      ),
    );
  }
}
