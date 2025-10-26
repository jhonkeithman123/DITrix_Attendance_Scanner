import 'package:flutter/material.dart';
import 'about_screen.dart';
import 'capture_id_screen.dart';
import '../widgets/id_scanner_widget.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
        ),
        title: Row(
          children: [
            Image.asset('assets/image/DITrix.jpg',
                height: 36, errorBuilder: (c, e, s) => const SizedBox()),
            const SizedBox(width: 10),
            const Text('DITrix Attendance Scanner'),
          ],
        ),
      ),
      drawer: Drawer(
        child: Container(
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: primary),
                child: Row(
                  children: [
                    Image.asset('assets/image/DITrix.jpg',
                        height: 48,
                        errorBuilder: (c, e, s) => const SizedBox()),
                    const SizedBox(width: 12),
                    const Text('DITrix',
                        style: TextStyle(color: Colors.white, fontSize: 20)),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.info, color: secondary),
                title: Text('About', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()));
                },
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Welcome',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const IdScannerWidget(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture ID'),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CaptureIdScreen())),
            ),
          ],
        ),
      ),
    );
  }
}
