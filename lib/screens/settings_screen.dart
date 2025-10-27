import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _developerMode = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _developerMode = prefs.getBool('developer_mode') ?? false;
      _themeMode = ThemeController.instance.themeMode.value;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('developer_mode', _developerMode);
    await ThemeController.instance.set(_themeMode);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  title: const Text('Theme'),
                  subtitle: const Text('Choose app appearance'),
                  trailing: DropdownButton<ThemeMode>(
                    value: _themeMode,
                    onChanged: (v) =>
                        setState(() => _themeMode = v ?? ThemeMode.system),
                    items: const [
                      DropdownMenuItem(
                          value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(
                          value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(
                          value: ThemeMode.dark, child: Text('Dark')),
                    ],
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Developer mode'),
                  subtitle:
                      const Text('Enable in-app debug logs and diagnostics'),
                  value: _developerMode,
                  onChanged: (v) => setState(() => _developerMode = v),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    onPressed: _save,
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
    );
  }
}
