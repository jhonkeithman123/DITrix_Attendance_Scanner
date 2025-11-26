import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <_Step>[
      _Step('Load masterlist (CSV)',
          'Open the menu • Load masterlist (CSV) to populate students.'),
      _Step('Set subject & times',
          'Open Settings to set Subject, Start, and Dismiss times.'),
      _Step('Capture IDs',
          'Use the camera to scan IDs. The app auto-matches by ID or surname.'),
      _Step('Export', 'Export attendance as CSV/XLSX from the menu.'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Skip',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: pages.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icons[i], size: 96),
                    const SizedBox(height: 24),
                    Text(pages[i].title,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(pages[i].desc, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages.length, (i) {
              final active = i == _page;
              return Container(
                width: active ? 28 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _page == pages.length - 1
                  ? _finish
                  : () => _ctrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut),
              child: Text(_page == pages.length - 1 ? 'Get started' : 'Next'),
            ),
          )
        ],
      ),
    );
  }
}

class _Step {
  final String title;
  final String desc;
  const _Step(this.title, this.desc);
}

const _icons = [
  Icons.file_upload,
  Icons.settings,
  Icons.camera_alt,
  Icons.download,
];
