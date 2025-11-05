import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:student_id_scanner/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_screen.dart';
import '../services/token_storage.dart';
import '../services/auth_service.dart';
import 'about_screen.dart';
import 'capture_id_screen.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import '../services/session_store.dart';
import '../models/session.dart';
import '../services/version_checker.dart';
import '../utils/app_notifier.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = SessionStore();
  final _auth = AuthService();
  List<Session> _sessions = [];
  bool _loading = true;
  bool _checkingProfile = false;
  bool _savingUploads = false;

  Uint8List? _profileAvatarBytes;
  String _profileInitial = 'K';
  Color _profileColor = Colors.grey;
  // ignore: unused_field
  String? _profileName;
  // ignore: unused_field
  String? _profileAvatarRaw;

  // new: control appbar title expansion when tapping the logo
  bool _appBarTitleExpanded = false;

  // ignore: unused_field
  bool _updateAvailable = false;
  // ignore: unused_field
  String _latestVersion = '';
  String? _updateUrl;

  static const String _versionCheckUrl =
      "https://raw.githubusercontent.com/jhonkeithman123/DITrix_Attendance_Scanner/main/app-version.json";

  @override
  void initState() {
    super.initState();
    _refresh();
    _checkForUpdate();
    _loadProfileInfo();
  }

  Future<void> _onProfileTap() async {
    if (_checkingProfile) return;
    setState(() => _checkingProfile = true);
    SharedPreferences? prefs;
    try {
      final token = await TokenStorage.getToken();
      if (token == null) {
        if (!mounted) return;
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }

      prefs = await SharedPreferences.getInstance();
      final localName = prefs.getString('profile_name');
      final hasLocalProfile = localName != null && localName.isNotEmpty;

      if (hasLocalProfile) {
        // optimistic navigation: show profile immediately, validate in background
        if (!mounted) return;
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        _validateSessionInBackground();
        return;
      }

      // no local profile -> validate first
      final profile = await _auth.validateSession();
      if (profile != null) {
        // persist profile locally for next time
        await prefs.setString(
            'profile_name', profile['name']?.toString() ?? '');
        await prefs.setString(
            'profile_email', profile['email']?.toString() ?? '');
        if (profile['avatar_url'] != null) {
          await prefs.setString(
              'profile_avatar', profile['avatar_url'].toString());
        }
        if (!mounted) return;
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        return;
      }

      // invalid session -> clear token and go to login
      await TokenStorage.deleteToken();
      if (!mounted) return;
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } catch (e) {
      // network/server error: if we had a local profile, still go to ProfileScreen; otherwise show error and stay
      // debugPrint('profile tap check error: $e');
      if (prefs != null && (prefs.getString('profile_name') ?? '').isNotEmpty) {
        if (!mounted) return;
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
      } else {
        if (!mounted) return;
        AppNotifier.showSnack(
            context, 'Could not validate session. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _checkingProfile = false);
    }
  }

  // validate session silently in background; if invalid -> force logout
  Future<void> _validateSessionInBackground() async {
    try {
      final profile = await _auth.validateSession();

      if (profile == null) {
        // token invalid/expired (server explicitly returned 401). Try refresh before forcing logout.
        final newExpiresIso = await _auth.refreshSession();
        if (newExpiresIso == null) {
          // refresh failed -> logout
          await TokenStorage.deleteToken();
          if (!mounted) return;
          AppNotifier.showSnack(
              context, 'Session expired — please sign in again');
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
          return;
        }

        // refresh succeeded: persist new expiry and update local profile by calling validateSession again
        try {
          final token = await TokenStorage.getToken();
          if (token != null) {
            final dt = DateTime.parse(newExpiresIso).toUtc();
            final epochMs = dt.millisecondsSinceEpoch;
            await TokenStorage.saveToken(token, expiresAtEpochMs: epochMs);
          }
        } catch (e) {
          // debugPrint('failed to persist refreshed expiry: $e');
        }

        // attempt to fetch profile again
        try {
          final refreshedProfile = await _auth.validateSession();
          if (refreshedProfile != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
                'profile_name', refreshedProfile['name']?.toString() ?? '');
            await prefs.setString(
                'profile_email', refreshedProfile['email']?.toString() ?? '');
            if (refreshedProfile['avatar_url'] != null) {
              await prefs.setString(
                  'profile_avatar', refreshedProfile['avatar_url'].toString());
            }
            if (mounted) _loadProfileInfo();
          }
        } catch (_) {
          // ignore - we've refreshed expiry and will not log out on transient errors
        }

        return;
      }

      // valid profile returned: update local profile & extend session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_name', profile['name']?.toString() ?? '');
      await prefs.setString(
          'profile_email', profile['email']?.toString() ?? '');
      if (profile['avatar_url'] != null) {
        await prefs.setString(
            'profile_avatar', profile['avatar_url'].toString());
      }

      final newExpiresIso = await _auth.refreshSession();
      if (newExpiresIso != null) {
        try {
          final dt = DateTime.parse(newExpiresIso).toUtc();
          final epochMs = dt.millisecondsSinceEpoch;
          final currentToken = await TokenStorage.getToken();
          if (currentToken != null) {
            await TokenStorage.saveToken(currentToken,
                expiresAtEpochMs: epochMs);
          }
        } catch (e) {
          // debugPrint('failed to persist refreshed expiry: $e');
        }
      }

      if (mounted) _loadProfileInfo();
      // ignore: unused_catch_clause
    } on Exception catch (e) {
      // network/server error — do not log the user out for transient errors.
      // debugPrint('background session validation failed (non-fatal): $e');
    }
  }

  Future<void> _loadProfileInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('profile_name') ?? '';
      final avatarRaw = prefs.getString('profile_avatar');

      // determine initials and color
      final initial = (name.trim().isNotEmpty) ? _initialsFromName(name) : 'K';
      final color = _colorForName(
          name.isNotEmpty ? name : (prefs.getString('profile_email') ?? ''));

      Uint8List? bytes;
      if (avatarRaw != null && avatarRaw.isNotEmpty) {
        final trimmed = avatarRaw.trim();
        if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
          try {
            final cleaned =
                trimmed.contains(',') ? trimmed.split(',').last : trimmed;
            final decoded = base64Decode(cleaned);
            if (decoded.isNotEmpty) bytes = decoded;
          } catch (_) {
            bytes = null;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _profileName = name.isNotEmpty ? name : null;
        _profileAvatarRaw = avatarRaw;
        _profileAvatarBytes = bytes;
        _profileInitial = initial;
        _profileColor = color;
      });
    } catch (e) {
      // ignore, keep defaults
    }
  }

  String _initialsFromName(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'K';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color _colorForName(String key) {
    final k = key.trim();
    final seed = k.isEmpty
        ? 0
        : k.runes.fold<int>(0, (h, c) => ((h * 31) + c) & 0x7fffffff);
    final hue = seed % 360;
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.5, 0.45).toColor();
  }

  Future<void> _checkForUpdate() async {
    try {
      final checker = VersionChecker(checkUrl: _versionCheckUrl);
      final info = await checker.check();

      if (!mounted) return;

      setState(() {
        _updateAvailable = info.updateAvailable;
        _latestVersion = info.latestVersion;
        _updateUrl = info.updateUrl;
      });

      // show user-visible message on every check/refresh using AppNotifier
      final message = info.updateAvailable
          ? 'Update available: v${info.latestVersion}'
          : 'App is up to date (v${info.currentVersion})';

      final action = info.updateAvailable && _updateUrl != null
          ? SnackBarAction(label: 'Update', onPressed: () => _openUpdateUrl())
          : null;

      if (mounted) AppNotifier.showSnack(context, message, action: action);
    } catch (e) {
      if (mounted) {
        AppNotifier.showSnack(context, 'Version check failed: $e');
      }
    }
  }

  Future<void> _openUpdateUrl() async {
    if (_updateUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No update URL available')));
      }
      return;
    }

    final uri = Uri.tryParse(_updateUrl!);
    if (uri == null) {
      if (mounted) {
        AppNotifier.showSnack(context, 'Malformed Url');
      }
      return;
    }

    try {
      // Prefer external application; some platforms may return false so fallback.
      var launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        launched = await launchUrl(uri);
      }
      if (!launched && mounted) {
        AppNotifier.showSnack(
            context, 'Could not open update URL: ${uri.toString()}');
      }
    } catch (e) {
      // show a short debug/feedback message
      if (mounted) {
        AppNotifier.showSnack(context, 'Failed to open update URL');
      }
    }
  }

  Future<void> _refresh() async {
    final list = await _store.list();

    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  Future<void> _startNewSession() async {
    final s = await _store.createNew();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaptureIdScreen(sessionId: s.id)),
    );
    await _refresh();
  }

  // new: delete a session
  Future<void> _deleteSession(dynamic id) async {
    try {
      await _store.delete(id);
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Session deleted');
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to delete session: $e');
    }
  }

  Future<void> _uploadSessions() async {
    if (_savingUploads) return;
    if (_sessions.isEmpty) {
      if (mounted) AppNotifier.showSnack(context, 'No sessions to upload');
      return;
    }

    setState(() => _savingUploads = true);
    try {
      // prepare payload for server. includes capture_id, subject, start_time, end_time
      final captures = _sessions.map((s) {
        return {
          'capture_id': s.id,
          'subject': s.subject,
          // map local model names to server expected keys
          'start_time': s.startTime,
          'end_time': s.endTime,
          'date': s.date,
        };
      }).toList();

      final uploaded = await _auth.uploadCaptures(captures);
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Uploaded $uploaded sessions');

      // optional: refresh local list (in case server returns changed state / you want to mark synced)
      await _refresh();
    } catch (e) {
      if (mounted) {
        AppNotifier.showSnack(context, 'Upload failed: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _savingUploads = false);
    }
  }

  bool _drawerTitleExpanded = false;

  Widget _buildProfileAvatar() {
    // If we have a valid decoded avatar image, use it; otherwise show generated initials avatar.
    if (_profileAvatarBytes != null && _profileAvatarBytes!.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          _profileAvatarBytes!,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) {
            return Text(_profileInitial,
                style: const TextStyle(color: Colors.black));
          },
        ),
      );
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _profileColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(_profileInitial,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
        ),
        // logo + animated title (size + fade). Tapping the logo toggles full title.
        title: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() {
                _appBarTitleExpanded = !_appBarTitleExpanded;
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/image/DITrix.jpg',
                  height: 36,
                  width: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => const SizedBox(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // make the title flexible so it can shrink and avoid overflow
            Flexible(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: _appBarTitleExpanded ? 260 : 84),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      _appBarTitleExpanded
                          ? 'DITrix Attendance Scanner'
                          : 'DITrix',
                      key: ValueKey<bool>(_appBarTitleExpanded),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Theme.of(context).appBarTheme.foregroundColor,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          // save/upload local capture sessions to server
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _savingUploads
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Save sessions to server',
                    onPressed: () async {
                      await _uploadSessions();
                    },
                    icon: const Icon(Icons.cloud_upload),
                  ),
          ),
          IconButton(
            tooltip: _updateAvailable ? 'Open update' : 'Check for updates',
            onPressed: () async {
              if (_updateAvailable && _updateUrl != null) {
                await _openUpdateUrl();
              } else {
                await _checkForUpdate();
              }
            },
            icon: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.system_update),
                if (_updateAvailable)
                  Positioned(
                    right: 0,
                    top: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // moved bottom action bar out of AppBar and into Scaffold
      bottomNavigationBar: BottomAppBar(
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // left: tutorial button
              IconButton(
                tooltip: 'Tutorial',
                icon: const Icon(Icons.school_outlined),
                color: Theme.of(context).colorScheme.onPrimary,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TutorialScreen()),
                  );
                },
              ),

              GestureDetector(
                onTap: _onProfileTap,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: _buildProfileAvatar(),
                ),
              ),

              // right: overflow menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                color: Theme.of(context).colorScheme.onPrimary,
                onSelected: (value) async {
                  switch (value) {
                    case 'settings':
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()));
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      drawer: Drawer(
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: primary),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() {
                        _drawerTitleExpanded = !_drawerTitleExpanded;
                      }),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/image/DITrix.jpg',
                          height: 48,
                          width: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const SizedBox(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _drawerTitleExpanded
                            ? Text('DITrix Attendance Scanner',
                                key: const ValueKey('full'),
                                style:
                                    TextStyle(color: onPrimary, fontSize: 20),
                                overflow: TextOverflow.ellipsis)
                            : Text('DITrix',
                                key: const ValueKey('short'),
                                style:
                                    TextStyle(color: onPrimary, fontSize: 20),
                                overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      color: onPrimary,
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Update reminder tile (shows only when update available)
              if (_updateAvailable)
                ListTile(
                  leading: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Icon(Icons.system_update,
                          color: Theme.of(context).colorScheme.secondary),
                      // small red dot badge
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text('Update available',
                      style: TextStyle(color: onSurface)),
                  subtitle: Text('v$_latestVersion',
                      style:
                          TextStyle(color: onSurface.withValues(alpha: 0.9))),
                  onTap: () async {
                    // show dialog with details and action
                    final open = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Update available'),
                        content: Text(
                            'A newer version (v$_latestVersion) is available. Would you like to update now?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Later')),
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Update')),
                        ],
                      ),
                    );
                    if (open == true) {
                      await _openUpdateUrl();
                    }
                  },
                ),

              ListTile(
                leading: Icon(Icons.info, color: secondary),
                title: Text('About', style: TextStyle(color: onSurface)),
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_sessions.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(
                          child: Text(
                              'No sessions yet. Start a new capture session.')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _sessions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final s = _sessions[i];
                      String fmtTime(String hhmm) => hhmm;
                      final subtitle =
                          '${s.subject.isEmpty ? 'Untitled' : s.subject} • In: ${fmtTime(s.startTime)} • Dismiss: ${fmtTime(s.endTime)}';
                      return ListTile(
                        tileColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        title: Text(
                          s.subject.isEmpty ? 'Session ${s.id}' : s.subject,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(subtitle),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete session',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete session'),
                                    content: const Text(
                                        'Are you sure you want to delete this session? This action cannot be undone.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _deleteSession(s.id);
                                }
                              },
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    CaptureIdScreen(sessionId: s.id)),
                          );
                          await _refresh();
                        },
                      );
                    },
                  )),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSession,
        label: const Text('Capture ID'),
      ),
    );
  }
}

// Simple tutorial screen added inline
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorial'),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DITrix Attendance Scanner — Quick Tutorial',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text(
              '1) Tap "Capture ID" to start a session and take photos of student IDs.'),
          const SizedBox(height: 8),
          const Text(
              '2) OCR extracts the student number and surname automatically. Confirm or correct if needed.'),
          const SizedBox(height: 8),
          const Text(
              '3) Use the session screen to mark present/late and export attendance as CSV/XLSX.'),
          const SizedBox(height: 8),
          const Text(
              '4) Enable Developer Mode in Settings to view diagnostics and logs.'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
