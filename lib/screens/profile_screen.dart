import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  final _emailCtl = TextEditingController();
  String _email = '';
  String? _avatarBase64;
  bool _loading = false;
  final _picker = ImagePicker();
  // ignore: unused_field
  final _auth = AuthService();

  // named listener so it can be removed cleanly
  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _nameCtl.addListener(_onNameChanged);
  }

  // helper: safely decode base64 or return null
  Uint8List? _tryDecodeAvatar(String? src) {
    if (src == null || src.isEmpty) return null;
    try {
      // strip data:<mime>;base64, prefix if present
      final cleaned = src.contains(',') ? src.split(',').last : src;
      final bytes = base64Decode(cleaned);
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      // debugPrint('avatar base64 decode failed: $e');
      return null;
    }
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('profile_avatar');
    setState(() {
      _nameCtl.text = prefs.getString('profile_name') ?? '';
      _email = prefs.getString('profile_email') ?? '';
      _emailCtl.text = _email;
      _avatarBase64 = stored;
    });

    // validate stored avatar: if it's a URL leave it, if base64 try decode else regenerate
    if (_avatarBase64 != null) {
      final trimmed = _avatarBase64!.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        // network url - nothing to do
        return;
      }
      final bytes = _tryDecodeAvatar(trimmed);
      if (bytes != null) {
        // valid base64 image
        return;
      }
      // invalid -> remove and regenerate
      // debugPrint('Invalid stored avatar, regenerating');
      _avatarBase64 = null;
      await prefs.remove('profile_avatar');
    }

    if (_avatarBase64 == null) {
      final initials = _initials();
      final bg = _colorForName();
      try {
        final pngBase64 = await _generateAvatarPngBase64(initials, bg, 256);
        setState(() => _avatarBase64 = pngBase64);
        await prefs.setString('profile_avatar', pngBase64);
      } catch (e) {
        // debugPrint('avatar generation failed: $e');
      }
    }
  }

// helper: compute initials from name or email
  String _initials() {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      if (_email.isNotEmpty) return _email[0].toUpperCase();
      return '?';
    }
    final parts =
        name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // helper: deterministic color from name/email
  Color _colorForName() {
    final key = (_nameCtl.text.isNotEmpty ? _nameCtl.text : _email).trim();
    final seed = key.isEmpty
        ? 0
        : key.runes.fold<int>(0, (int h, int c) => ((h * 31) + c) & 0x7fffffff);
    final hue = seed % 360;
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.5, 0.45).toColor();
  }

  // generate a PNG (RGBA) with initials centered on colored background
  Future<String> _generateAvatarPngBase64(
      String initials, Color bg, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = bg;
    final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
    final rrect = RRect.fromRectXY(rect, size / 2, size / 2);
    canvas.drawRRect(rrect, paint);

    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: size * 0.42,
      fontWeight: FontWeight.w600,
    );
    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.center);
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(initials);
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: size.toDouble()));

    final double dx = (size - paragraph.maxIntrinsicWidth) / 2;
    final double dy = (size - paragraph.height) / 2;
    canvas.drawParagraph(paragraph, Offset(dx, dy));

    final picture = recorder.endRecording();
    final img = await picture.toImage(size, size);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    return base64Encode(bytes);
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

    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      final trimmed = _avatarBase64!.trim();
      try {
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          child = CircleAvatar(
            radius: 46,
            backgroundImage: NetworkImage(trimmed),
          );
        } else {
          final bytes = _tryDecodeAvatar(trimmed);
          if (bytes != null) {
            child = CircleAvatar(
              radius: 46,
              backgroundImage: MemoryImage(bytes),
            );
          } else {
            throw Exception('Decoded bytes null');
          }
        }
      } catch (err) {
        // debugPrint('MemoryImage/NetworkImage failed, falling back to initials: $err');
        child = _initialsAvatar();
      }
    } else {
      child = _initialsAvatar();
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

  // small helper to create initials avatar widget (kept separate for reuse)
  Widget _initialsAvatar() {
    final bg = _colorForName();
    final initials = _initials();
    return CircleAvatar(
      radius: 46,
      backgroundColor: bg,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
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
      // first try server update
      try {
        await _auth.updateProfile(
            name: _nameCtl.text.trim(), avatarBase64: _avatarBase64);
      } catch (e) {
        // debugPrint('profile server update failed: $e');
        // fail early if you want strict behavior; here we continue and still save locally
        throw Exception('Server update failed');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_name', _nameCtl.text.trim());

      if (_avatarBase64 != null) {
        await prefs.setString('profile_avatar', _avatarBase64!);
      } else {
        await prefs.remove('profile_avatar');
      }

      if (!mounted) return;
      AppNotifier.showSnack(context, 'Profile saved');
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
    _nameCtl.removeListener(_onNameChanged);
    _nameCtl.dispose();
    _emailCtl.dispose();
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
                  // display client email (read-only)
                  TextFormField(
                    controller: _emailCtl,
                    enabled: false,
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
