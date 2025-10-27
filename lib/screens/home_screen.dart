import 'package:flutter/material.dart';

import 'about_screen.dart';
import 'capture_id_screen.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import '../services/session_store.dart';
import '../models/session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = SessionStore();
  List<Session> _sessions = [];
  bool _loading = true;

  // new: control appbar title expansion when tapping the logo
  bool _appBarTitleExpanded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session deleted')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete session: $e')),
      );
    }
  }

  bool _drawerTitleExpanded = false;

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
        // logo + compact title. Tapping the logo toggles full title.
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
            // smaller text to fit menus; expands to full label when toggled
            Text(
              _appBarTitleExpanded ? 'DITrix Attendance Scanner' : 'DITrix',
              style: TextStyle(
                color: Theme.of(context).appBarTheme.foregroundColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tutorial',
            icon: const Icon(Icons.school_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TutorialScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
