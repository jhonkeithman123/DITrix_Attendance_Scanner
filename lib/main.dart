import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:student_id_scanner/screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

// ...existing code...
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final showOnboarding = !(prefs.getBool('onboarding_done') ?? false);
  runApp(StudentIdScannerApp(showOnboarding: showOnboarding));
}

class StudentIdScannerApp extends StatelessWidget {
  const StudentIdScannerApp({super.key, required this.showOnboarding});
  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
        seedColor: AppColors.seedLight, brightness: Brightness.light);
    final darkScheme = ColorScheme.fromSeed(
        seedColor: AppColors.seedDark, brightness: Brightness.dark);

    return MaterialApp(
      title: 'DITrix Attendance Scanner',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        scaffoldBackgroundColor: Colors.transparent, // let gradient show
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: Colors.transparent, // let gradient show
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.of(context)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
