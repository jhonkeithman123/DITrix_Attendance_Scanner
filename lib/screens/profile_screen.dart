import 'dart:convert';
// ignore: unused_import
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_notifier.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtl = TextEditingController();
  String _email = '';
  String? _avatarBase64;
  bool _loading = false;
  final _picker = ImagePicker();
  // ignore: unused_field
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtl.text = prefs.getString('profile_name') ?? '';
      _email = prefs.getString('profile_email') ?? '';
      _avatarBase64 = prefs.getString('profile_avatar');
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (file == null) return;
      final bytes = await file.readAsBytes();
      final base64Str = base64Encode(bytes);

      setState(() {
        _avatarBase64 = base64Str;
      });
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to pick image');
    }
  }

  Widget _buildAvatar() {
    Widget child;

    if (_avatarBase64 != null) {
      try {
        final bytes = base64Decode(_avatarBase64!);
        child = CircleAvatar(
          radius: 46,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        child =
            const CircleAvatar(radius: 46, child: Icon(Icons.person, size: 42));
      }
    } else {
      child =
          const CircleAvatar(radius: 46, child: Icon(Icons.person, size: 42));
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        child,
        Material(
          elevation: 2,
          shape: const CircleBorder(),
          color: Theme.of(context).colorScheme.primary,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _showImageOptions(),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.edit, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Remove avatar'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _avatarBase64 = null);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_name', _nameCtl.text.trim());

      if (_avatarBase64 != null) {
        await prefs.setString('profile_avatar', _avatarBase64!);
      } else {
        await prefs.remove('profile_avatar');
      }

      // TODO: implement server sync, updateProfile on AuthService.
      try {
        // If AuthService has updateProfile(email,name,avatarBase64) implement it there.
        // await _auth.updateProfile(email: _email, name: _nameCtl.text.trim(), avatarBase64: _avatarBase64);
      } catch (_) {
        // ignore server sync failure for now; local save is primary
      }

      if (!mounted) return;
      AppNotifier.showSnack(context, 'Profile saved locally');
    } catch (_) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to save profile');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    // preserve optional profile fields or clear them based on your UX needs:
    // await prefs.remove('profile_name');
    // await prefs.remove('profile_email');
    // await prefs.remove('profile_avatar');

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _buildAvatar();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  avatar,
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    enabled: false,
                    initialValue: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _saveProfile,
                      icon: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Save Profile'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Avatar and name are stored locally. Server sync will be implemented in the future updates.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
