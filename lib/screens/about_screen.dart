import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _build = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
        ),
      ),
      body: ListView(
        children: [
          Container(
            decoration: BoxDecoration(gradient: AppGradients.of(context)),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/image/DITrix.jpg',
                    height: 72,
                    width: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      height: 72,
                      width: 72,
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.badge, color: cs.onPrimary),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'DITrix Attendance Scanner',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).appBarTheme.foregroundColor,
                          fontWeight: FontWeight.w600,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Version card
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Version'),
                    subtitle: Text(
                      (_version.isEmpty && _build.isEmpty)
                          ? 'Loading…'
                          : 'v$_version ($_build)',
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Overview
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Overview',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        SizedBox(height: 8),
                        Text(
                          'DITrix Attendance Scanner streamlines attendance by scanning student IDs, '
                          'recognizing text on-device, and organizing sessions by subject and schedule.',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Features
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Features',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _bullet('Scan IDs via camera and ML Kit OCR'),
                        _bullet('Auto-extract Student ID and surname'),
                        _bullet(
                            'Session-based saving (subject, in/dismiss times, roster)'),
                        _bullet('Export attendance (CSV/XLSX)'),
                        _bullet('Dark/Light with green gradient theme'),
                        _bullet('Developer mode for diagnostics'),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Quick actions
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      spacing: 8,
                      overflowSpacing: 8,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.description),
                          label: const Text('Licenses'),
                          onPressed: () => showLicensePage(
                            context: context,
                            applicationName: 'DITrix Attendance Scanner',
                            applicationVersion:
                                _version.isEmpty ? null : 'v$_version',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
