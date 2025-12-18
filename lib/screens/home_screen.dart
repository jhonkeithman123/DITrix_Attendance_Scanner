import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/session.dart';
import '../services/token_storage.dart';
import '../services/auth_service.dart';
import '../services/session_store.dart';
import '../services/version_checker.dart';
import '../services/shared_capture.dart';
import '../theme/app_theme.dart';
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

  final _sharedService = SharedCaptureService();
  List<Map<String, dynamic>> _ownedCaptures = [];
  List<Map<String, dynamic>> _sharedCaptures = [];
  // ignore: unused_field
  int _tabIndex = 0;

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

  // track authenticated state for conditional UI in shared tabs
  bool _authenticated = false;
  bool _loadingProfileInfo = false;

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
      print('[HomeScreen] _onProfileTap start');

      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        if (!mounted) return;
        Navigator.pushNamed(context, '/login');
        return;
      }

      prefs = await SharedPreferences.getInstance();
      final localName = prefs.getString('profile_name');
      final hasLocalProfile = localName != null && localName.isNotEmpty;

      if (hasLocalProfile) {
        print(
            '[HomeScreen] using local cached profile, navigating optimistically');
        // optimistic navigation: show profile immediately, validate in background
        if (!mounted) return;
        await Navigator.pushNamed(context, '/profile');
        // refresh avatar after returning
        if (mounted) await _loadProfileInfo();
        _validateSessionInBackground();
        return;
      }

      // no local profile -> validate first
      print('[HomeScreen] no local profile, validating session with server');
      final profile = await _auth.validateSession();
      print('[HomeScreen] validateSession result: ${profile != null}');
      if (profile != null) {
        print(
            '[HomeScreen] session valid, saving local profile and navigating');
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
        await Navigator.pushNamed(context, '/profile');
        if (mounted) await _loadProfileInfo();
        return;
      }

      // invalid session -> clear token and go to login
      print(
          '[HomeScreen] session invalid -> deleting token and navigating to login');
      await FirebaseAuth.instance.signOut();
      await TokenStorage.deleteToken();
      if (!mounted) return;
      Navigator.pushNamed(context, '/login');
    } catch (e) {
      print('[HomeScreen] _onProfileTap error: $e');
      // network/server error: if we had a local profile, still go to ProfileScreen; otherwise show error and stay
      // debugPrint('profile tap check error: $e');
      if (prefs != null && (prefs.getString('profile_name') ?? '').isNotEmpty) {
        if (!mounted) return;
        Navigator.pushNamed(context, '/profile');
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
      print('[HomeScreen] background session validation start');
      final profile = await _auth.validateSession();

      if (profile == null) {
        print(
            '[HomeScreen] background validateSession returned null -> trying refresh');
        // token invalid/expired (server explicitly returned 401). Try refresh before forcing logout.
        final newExpiresIso = await _auth.refreshSession();
        print('[HomeScreen] refreshSession result: $newExpiresIso');
        if (newExpiresIso == null) {
          // refresh failed -> logout
          await TokenStorage.deleteToken();
          if (!mounted) return;
          AppNotifier.showSnack(
              context, 'Session expired — please sign in again');
          Navigator.pushNamed(context, '/login');
          return;
        }
        print('[HomeScreen] refresh succeeded, persisted new expiry');
        // refresh succeeded: persist new expiry and update local profile by calling validateSession again
        try {
          final token = await TokenStorage.getToken();
          if (token != null) {
            final dt = DateTime.parse(newExpiresIso).toUtc();
            final epochMs = dt.millisecondsSinceEpoch;
            await TokenStorage.saveToken(token, expiresAtEpochMs: epochMs);
          }
        } catch (e) {
          print('[HomeScreen] failed to persist refreshed expiry: $e');
          // debugPrint('failed to persist refreshed expiry: $e');
        }

        // attempt to fetch profile again
        try {
          final refreshedProfile = await _auth.validateSession();
          print(
              '[HomeScreen] post-refresh validateSession returned: ${refreshedProfile != null}');
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

      print('[HomeScreen] background validateSession ok, extending session');
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
      print('[HomeScreen] refreshSession returned: $newExpiresIso');
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
          print('[HomeScreen] failed to persist refresh expiry: $e');
          // debugPrint('failed to persist refreshed expiry: $e');
        }
      }

      if (mounted) _loadProfileInfo();
      // ignore: unused_catch_clause
    } on Exception catch (e) {
      print('[HomeScreen] background session validation error (ignored): $e');
      // network/server error — do not log the user out for transient errors.
      // debugPrint('background session validation failed (non-fatal): $e');
    }
  }

  Future<void> _loadProfileInfo() async {
    if (_loadingProfileInfo) return;
    _loadingProfileInfo = true;
    setState(() => _checkingProfile = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final fbUser = FirebaseAuth.instance.currentUser;

      final storedName = prefs.getString('profile_name');
      final name = (storedName != null && storedName.isNotEmpty)
          ? storedName
          : (fbUser?.displayName ?? '');
      final storedAvatar = prefs.getString('profile_avatar');
      String avatarRaw = storedAvatar ?? '';

      if (avatarRaw.isEmpty && (fbUser?.photoURL?.isNotEmpty ?? false)) {
        avatarRaw = fbUser!.photoURL!;
        await prefs.setString('profile_avatar', avatarRaw);
      }

      _profileName = name;
      _profileInitial =
          _initialsFromName(name).isEmpty ? 'K' : _initialsFromName(name);
      _profileColor = _colorForName(name);
      _profileAvatarBytes = null;
      _profileAvatarRaw = null;

      if (avatarRaw.isNotEmpty) {
        final trimmed = avatarRaw.trim();
        if (trimmed.startsWith('data:')) {
          // data:<mime>;base64,...
          final idx = trimmed.indexOf(',');
          if (idx != -1) {
            final b64 = trimmed.substring(idx + 1);
            try {
              _profileAvatarBytes = base64Decode(b64);
            } catch (_) {
              _profileAvatarBytes = null;
            }
          }
        } else if (trimmed.startsWith('http://') ||
            trimmed.startsWith('https://')) {
          // prefer to use the remote URL as-is (NetworkImage)
          _profileAvatarRaw = trimmed;
        } else {
          // maybe plain base64 without data: prefix
          try {
            _profileAvatarBytes = base64Decode(trimmed);
          } catch (_) {
            // fallback: try fetching as URL
            try {
              final uri = Uri.parse(avatarRaw);
              final resp =
                  await http.get(uri).timeout(const Duration(seconds: 8));
              if (resp.statusCode == 200) _profileAvatarBytes = resp.bodyBytes;
            } catch (_) {
              _profileAvatarBytes = null;
              _profileAvatarRaw = null;
            }
          }
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      print('[HomeScreen] _loadProfileInfo error: $e');
    } finally {
      if (mounted) setState(() => _checkingProfile = false);
      _loadingProfileInfo = false;
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

  Future<void> _startNewSession() async {
    final s = await _store.createNew();
    if (!mounted) return;
    await Navigator.pushNamed(context, '/capture',
        arguments: {'sessionId': s.id});
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

  /// Open a multi-select dialog for uploading local sessions into shared captures.
  Future<void> _openUploadChooser() async {
    print('[HomeScreen] _openUploadChooser called');
    if (mounted) AppNotifier.showSnack(context, 'Opening upload chooser...');
    final sessions = List<Session>.from(_sessions);
    if (sessions.isEmpty) {
      if (mounted) {
        AppNotifier.showSnack(context, 'No local sessions to upload');
      }
      return;
    }

    // Build initial selection map
    final selected = <String, bool>{};
    for (final s in sessions) {
      selected[s.id] = false;
    }

    String? chosenSharedId;
    bool createNewShared = false;
    final newSharedSubjectCtl = TextEditingController();
    String? _subjectError;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx2, setState2) {
          bool subjectIsDuplicate(String v) {
            final s = v.trim().toLowerCase();
            if (s.isEmpty) return false;
            return _ownedCaptures.any((c) {
              final subj =
                  (c['subject'] as String?)?.trim().toLowerCase() ?? '';
              return subj.isNotEmpty && subj == s;
            });
          }

          void validateSubject(String v) {
            if (v.trim().isEmpty) {
              setState2(() => _subjectError = 'Subject required');
              return;
            }
            if (subjectIsDuplicate(v)) {
              setState2(() => _subjectError =
                  'You already have a shared session with this subject');
              return;
            }
            setState2(() => _subjectError = null);
          }

          final screenW = MediaQuery.of(ctx).size.width;
          final screenH = MediaQuery.of(ctx).size.height;
          final dialogW = math.min(560.0, screenW - 48.0);
          final dialogMaxH = math.min(screenH * 0.85, 800.0);

          // compute list height based on items (no huge empty gap)
          final itemHeight = 72.0;
          final visibleItems = (sessions.length).clamp(1, 8);
          final listHeight =
              math.min(dialogMaxH * 0.6, visibleItems * itemHeight + 8.0);

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: dialogW, maxHeight: dialogMaxH),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6.0),
                      child: Text('Upload sessions',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                    ),

                    // sessions list (bounded height)
                    SizedBox(
                      height: listHeight,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        physics: sessions.length > visibleItems
                            ? const AlwaysScrollableScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        itemCount: sessions.length,
                        itemBuilder: (_, idx) {
                          final s = sessions[idx];
                          return CheckboxListTile(
                            title: Text(s.subject.isEmpty
                                ? 'Session ${s.id}'
                                : s.subject),
                            subtitle: Text(
                                '${s.date} • ${s.startTime} - ${s.endTime}'),
                            value: selected[s.id],
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            onChanged: (v) =>
                                setState2(() => selected[s.id] = v ?? false),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 8),

                    // dropdown (expand to dialog width)
                    Builder(builder: (ddCtx) {
                      final menuItemHeight = 48.0;
                      final visibleMenuItems =
                          (_ownedCaptures.length + 1).clamp(1, 6);
                      final menuMax = math
                          .min(dialogMaxH * 0.35,
                              (visibleMenuItems * menuItemHeight) + 24.0)
                          .clamp(120.0, 520.0);

                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        isDense: true,
                        itemHeight: menuItemHeight,
                        menuMaxHeight: menuMax,
                        value: chosenSharedId,
                        hint: const Text(
                            'Select existing shared session (optional)',
                            overflow: TextOverflow.ellipsis),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          ..._ownedCaptures.map((c) {
                            final id = c['id']?.toString() ?? '';
                            final title =
                                (c['subject'] as String?)?.isNotEmpty == true
                                    ? c['subject']
                                    : 'Session $id';
                            return DropdownMenuItem(
                                value: id,
                                child: Text(title,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1));
                          }),
                        ],
                        onChanged: (v) => setState2(() {
                          chosenSharedId = v;
                          createNewShared = false;
                        }),
                      );
                    }),

                    const SizedBox(height: 6),

                    Row(children: [
                      Checkbox(
                        value: createNewShared,
                        onChanged: (v) => setState2(() {
                          createNewShared = v ?? false;
                          if (createNewShared) chosenSharedId = null;
                        }),
                      ),
                      const Flexible(
                          child: Text('Create new shared capture for uploads')),
                    ]),

                    if (createNewShared)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: newSharedSubjectCtl,
                          onChanged: (v) => validateSubject(v),
                          decoration: InputDecoration(
                            labelText: 'Subject for new shared capture',
                            errorText: _subjectError,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx2).pop(),
                            child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final toUpload = sessions
                                .where((s) => selected[s.id] == true)
                                .toList();
                            if (toUpload.isEmpty) {
                              AppNotifier.showSnack(
                                  context, 'Select at least one session');
                              return;
                            }
                            if (createNewShared) {
                              final subj = newSharedSubjectCtl.text.trim();
                              validateSubject(subj);
                              if (_subjectError != null) {
                                AppNotifier.showSnack(context, _subjectError!);
                                return;
                              }
                            }
                            Navigator.of(ctx2).pop();
                            await _uploadSelectedToShared(
                                toUpload,
                                chosenSharedId,
                                createNewShared
                                    ? newSharedSubjectCtl.text.trim()
                                    : null);
                          },
                          child: const Text('Upload selected'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      );
    } catch (e) {
      print('[HomeScreen] _openUploadChooser error: $e');
      if (mounted) {
        AppNotifier.showSnack(context, 'Failed to open upload chooser: $e');
      }
    }
  }

  Future<void> _refresh() async {
    final localList = await _store.list();

    // Fetch shared captures if authenticated
    try {
      final isAuth = FirebaseAuth.instance.currentUser != null;
      print('[HomeScreen] refresh - firebase present: $isAuth');
      // update auth flag for builders
      if (mounted) setState(() => _authenticated = isAuth);
      if (isAuth) {
        final result = await _sharedService.listCaptures();
        print('[HomeScreen] listCaptures result: $result');
        if (!mounted) return;

        // Safely extract and filter arrays
        final ownedRaw = result['owned'];
        final sharedRaw = result['shared'];

        final ownedList = (ownedRaw is List &&
                ownedRaw.isNotEmpty &&
                ownedRaw.first is List)
            ? (ownedRaw.first as List)
                .whereType<Map<String, dynamic>>()
                .toList()
            : (ownedRaw as List?)?.whereType<Map<String, dynamic>>().toList() ??
                [];

        final sharedList = (sharedRaw is List &&
                sharedRaw.isNotEmpty &&
                sharedRaw.first is List)
            ? (sharedRaw.first as List)
                .whereType<Map<String, dynamic>>()
                .toList()
            : (sharedRaw as List?)
                    ?.whereType<Map<String, dynamic>>()
                    .toList() ??
                [];

        setState(() {
          _ownedCaptures = ownedList;
          _sharedCaptures = sharedList;
          print(
              '[HomeScreen] owned: ${_ownedCaptures.length}, shared: ${_sharedCaptures.length}');
        });
      } else {
        // not authenticated: clear lists
        if (mounted) {
          setState(() {
            _ownedCaptures = [];
            _sharedCaptures = [];
          });
        }
      }
    } catch (e) {
      print('[HomeScreen] _refresh error: $e');
      // Ignore if not authenticated or server error
    }

    if (!mounted) return;
    setState(() {
      _sessions = localList;
      _loading = false;
    });
  }

  /// Manual refetch wrapper used by AppBar refresh button.
  /// Also shows simple feedback and prevents overlapping refreshes.
  Future<void> _refetch() async {
    if (_loading) return; // already refreshing
    if (mounted) setState(() => _loading = true);
    try {
      await _refresh();
      if (mounted) AppNotifier.showSnack(context, 'Refreshed');
    } catch (e) {
      if (mounted) AppNotifier.showSnack(context, 'Refresh failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
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

    if (_profileAvatarRaw != null && _profileAvatarRaw!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          _profileAvatarRaw!,
          width: 28,
          height: 28,
          fit: BoxFit.cover,
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
          // Refresh button to trigger a manual refetch (in addition to pull-down)
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              tooltip: 'Refresh',
              onPressed: _refetch,
              icon: const Icon(Icons.refresh),
            ),
          ),
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
                      await _openUploadChooser();
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
                  Navigator.pushNamed(context, '/tutorial');
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
                      Navigator.pushNamed(context, '/settings');
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
                        Navigator.pushNamed(context, '/settings');
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
                  Navigator.pushNamed(context, '/about');
                },
              ),
            ],
          ),
        ),
      ),
      body: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              TabBar(
                onTap: (index) => setState(() => _tabIndex = index),
                tabs: const [
                  Tab(text: 'Local', icon: Icon(Icons.phone_android)),
                  Tab(text: 'My Shared', icon: Icon(Icons.cloud)),
                  Tab(text: 'Joined', icon: Icon(Icons.group)),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          children: [
                            _buildLocalList(),
                            _buildOwnedList(),
                            _buildSharedList(),
                          ],
                        ),
                ),
              ),
            ],
          )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewSession,
        label: const Text('Capture ID'),
      ),
    );
  }

  Widget _buildLocalList() {
    if (_sessions.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No local sessions yet')),
        ],
      );
    }

    return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final s = _sessions[i];
          final subtitle =
              '${s.subject.isEmpty ? 'Untitled' : s.subject} • ${s.startTime} - ${s.endTime}';

          return ListTile(
            tileColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            title: Text(s.subject.isEmpty ? 'Session ${s.id}' : s.subject),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: 'Upload to cloud',
                  onPressed: () => _uploadSingleSession(s),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDeleteLocal(s.id),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.pushNamed(context, '/capture',
                  arguments: {'sessionId': s.id});
              await _refresh();
            },
          );
        });
  }

  Widget _buildOwnedList() {
    if (!_authenticated) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Center(child: Text('Log in to use this feature')),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              child: const Text('Log in'),
            ),
          ),
        ],
      );
    }

    if (_ownedCaptures.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No cloud sessions yet. Upload a local session.')),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _ownedCaptures.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = _ownedCaptures[i];

        // Safely extract fields
        final captureId = c['id']?.toString();
        if (captureId == null || captureId.isEmpty) {
          return const SizedBox.shrink(); // skip invalid item
        }
        final subject = (c['subject'] as String?)?.trim();
        final title = (subject != null && subject.isNotEmpty)
            ? subject
            : 'Session $captureId';
        final shareCode = (c['share_code'] as String?) ?? '';

        return ListTile(
          tileColor: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text(title),
          subtitle: Text(
            shareCode.isNotEmpty ? 'Code: $shareCode' : 'No share code',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share',
                onPressed: () => _showShareDialog(c),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: () => _confirmDeleteShared(captureId),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => Navigator.pushNamed(
            context,
            '/shared-capture',
            arguments: {'captureId': captureId},
          ),
        );
      },
    );
  }

  Widget _buildSharedList() {
    if (!_authenticated) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Center(child: Text('Log in to use this feature')),
          const SizedBox(height: 12),
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              child: const Text('Log in'),
            ),
          ),
        ],
      );
    }

    if (_sharedCaptures.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          const Center(child: Text('No shared sessions. Join with a code.')),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Join Session'),
              onPressed: _showJoinDialog,
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sharedCaptures.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = _sharedCaptures[i];
        final subject = c['subject'] ?? 'Untitled';
        final ownerName = c['owner_name'] ?? 'Unknown';
        return ListTile(
          tileColor: Theme.of(context)
              .colorScheme
              .secondaryContainer
              .withValues(alpha: 0.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text(subject),
          subtitle: Text('Owner: $ownerName'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openSharedCapture(c['id']),
        );
      },
    );
  }

  Future<void> _uploadSingleSession(Session s) async {
    try {
      final roster = s.roster
          .map((r) => {
                'id': r['id'],
                'name': r['name'],
                'present': r['present'] ?? false,
                'time': r['time'],
                'status': r['status'],
              })
          .toList();

      final result = await _sharedService.createCapture(
        id: s.id,
        subject: s.subject,
        date: s.date,
        startTime: s.startTime,
        endTime: s.endTime,
        roster: roster,
      );

      if (!mounted) return;

      final shareCode = result['shareCode'] ??
          result['share_code'] ??
          (result['capture']?['share_code']);

      AppNotifier.showSnack(context,
          shareCode != null ? 'Uploaded: $shareCode' : 'Uploaded session');
      await _refresh(); // This calls _refresh() which should populate _ownedCaptures
    } catch (e) {
      if (!mounted) return;
      final errorMsg = e.toString();
      // Check if it's a duplicate error (409)
      if (errorMsg.contains('already been uploaded')) {
        AppNotifier.showSnack(
          context,
          'This capture has already been uploaded. Try a different session.',
        );
      } else {
        AppNotifier.showSnack(context, 'Upload failed: $errorMsg');
      }
    }
  }

  /// Upload selected local sessions to shared captures.
  Future<void> _uploadSelectedToShared(List<Session> selectedSessions,
      String? existingSharedId, String? newSharedSubject) async {
    setState(() => _savingUploads = true);
    try {
      // if user requested a new shared capture, create one per session (or one shared capture for all? - we'll create one per session to keep previous semantics)
      for (final s in selectedSessions) {
        try {
          final result = await _sharedService.createCapture(
            id: s.id,
            subject: s.subject.isNotEmpty
                ? s.subject
                : (newSharedSubject ?? 'Session ${s.id}'),
            date: s.date,
            startTime: s.startTime,
            endTime: s.endTime,
            roster: s.roster
                .map((r) => {
                      'id': r['id'],
                      'name': r['name'],
                      'present': r['present'] ?? false,
                      'time': r['time'],
                      'status': r['status'],
                    })
                .toList(),
            // if existingSharedId is provided we still call createCapture - server may decide to update/merge
          );
          if (!mounted) return;
          final shareCode = result['shareCode'] ??
              result['share_code'] ??
              (result['capture']?['share_code']);

          AppNotifier.showSnack(
              context, 'Uploaded ${s.id} -> ${shareCode ?? 'ok'}');
        } catch (e) {
          AppNotifier.showSnack(context, 'Failed to upload ${s.id}: $e');
        }
      }
      await _refresh();
    } finally {
      if (mounted) setState(() => _savingUploads = false);
    }
  }

  Future<void> _confirmDeleteLocal(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete local session'),
        content: const Text('This will only delete the local copy.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await _deleteSession(id);
    }
  }

  Future<void> _confirmDeleteShared(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shared session'),
        content: const Text('This will delete for all collaborators.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _sharedService.deleteCapture(id);
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Deleted');
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        AppNotifier.showSnack(context, 'Delete failed: $e');
      }
    }
  }

  Future<void> _showShareDialog(Map<String, dynamic> capture) async {
    final emailCtl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share Code: ${capture['share_code']}'),
            const SizedBox(height: 16),
            TextField(
              controller: emailCtl,
              decoration:
                  const InputDecoration(labelText: 'Collaborator Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sharedService.addCollaborator(
                    capture['id'], emailCtl.text.trim());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                AppNotifier.showSnack(context, 'Collaborator added');
              } catch (e) {
                if (!mounted) return;
                AppNotifier.showSnack(context, 'Failed: $e');
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinDialog() async {
    final codeCtl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask the owner for the share code'),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtl,
              decoration: const InputDecoration(
                labelText: 'Share Code',
                hintText: 'e.g., ABC12345',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sharedService
                    .joinByCode(codeCtl.text.trim().toUpperCase());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                AppNotifier.showSnack(context, 'Joined successfully');
                await _refresh();
              } catch (e) {
                if (!mounted) return;
                AppNotifier.showSnack(context, 'Failed: $e');
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  void _openSharedCapture(String id) {
    // Navigate to a read-only or editable view depending on role
    Navigator.pushNamed(context, '/shared-capture',
        arguments: {'captureId': id});
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
