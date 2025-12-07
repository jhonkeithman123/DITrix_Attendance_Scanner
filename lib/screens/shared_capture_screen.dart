import 'package:flutter/material.dart';
import '../services/shared_capture.dart';
import '../theme/app_theme.dart';
import '../utils/app_notifier.dart';
import 'capture_id_screen.dart';

class SharedCaptureScreen extends StatefulWidget {
  final String captureId;
  const SharedCaptureScreen({super.key, required this.captureId});

  @override
  State<SharedCaptureScreen> createState() => _SharedCaptureScreenState();
}

class _SharedCaptureScreenState extends State<SharedCaptureScreen>
    with WidgetsBindingObserver {
  final _service = SharedCaptureService();

  Map<String, dynamic>? _capture;
  List<Map<String, dynamic>> _roster = [];
  List<Map<String, dynamic>> _collaborators = [];
  bool _loading = true;
  bool _isDirty = false;
  String _userRole = 'viewer';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCapture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _promptSaveIfDirty();
    }
  }

  Future<bool?> _promptSaveIfDirty() async {
    if (!_isDirty || !mounted) return null;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes. Do you want to save?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCapture() async {
    try {
      final data = await _service.getCapture(widget.captureId);
      if (!mounted) return;

      final capture = data['capture'] as Map<String, dynamic>;
      final roster = List<Map<String, dynamic>>.from(capture['roster'] ?? []);
      final collaborators =
          List<Map<String, dynamic>>.from(capture['collaborators'] ?? []);
      final role = (capture['role'] ?? 'viewer').toString();

      setState(() {
        _capture = capture;
        _roster = roster;
        _collaborators = collaborators;
        _userRole = role;
        _loading = false;
        _isDirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to load capture: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_isDirty || _capture == null) return;

    try {
      AppNotifier.showLoading(context, message: 'Saving...');
      await _service.updateCapture(
        widget.captureId,
        subject: _capture!['subject'],
        date: _capture!['date'],
        startTime: _capture!['start_time'],
        endTime: _capture!['end_time'],
        roster: _roster,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading
      AppNotifier.showSnack(context, 'Saved successfully');
      setState(() => _isDirty = false);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading
      AppNotifier.showSnack(context, 'Save failed: $e');
    }
  }

  Future<void> _showInviteDialog() async {
    try {
      final students = await _service.getAllStudents();
      if (!mounted) return;

      // Filter out already added collaborators
      final collaboratorIds = {
        _capture!['owner_id'],
        ..._collaborators.map((c) => c['id'])
      };
      final available =
          students.where((s) => !collaboratorIds.contains(s['id'])).toList();

      if (available.isEmpty) {
        AppNotifier.showSnack(context, 'No more students to invite');
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite students'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: available.length,
              itemBuilder: (_, i) {
                final student = available[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text((student['name'] ?? '').toString().isNotEmpty
                        ? (student['name'] ?? '').toString()[0].toUpperCase()
                        : '?'),
                  ),
                  title: Text(student['name'] ?? ''),
                  subtitle: Text(student['email'] ?? ''),
                  trailing: const Icon(Icons.add),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _addCollaborator(student);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add by Email'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _showAddByEmailDialog();
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to load students: $e');
    }
  }

  /// Manually add a user by email (for users not in the system yet)
  Future<void> _showAddByEmailDialog() async {
    final emailCtl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add by Email'),
        content: TextField(
          controller: emailCtl,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'user@example.com',
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailCtl.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                AppNotifier.showSnack(context, 'Invalid email');
                return;
              }
              Navigator.pop(ctx);
              try {
                AppNotifier.showLoading(context, message: 'Adding...');
                await _service.addCollaborator(
                  widget.captureId,
                  email,
                  role: 'viewer',
                );
                if (!mounted) return;
                Navigator.pop(context); // Close loading
                AppNotifier.showSnack(context, 'Invited $email');
                await _loadCapture();
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context); // Close loading
                AppNotifier.showSnack(context, 'Failed: $e');
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCollaborator(Map<String, dynamic> student) async {
    try {
      await _service.addCollaborator(
        widget.captureId,
        student['email'] as String,
        role: 'viewer',
      );

      if (!mounted) return;
      AppNotifier.showSnack(context, 'Invited ${student['name']}');
      await _loadCapture();
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to invite: $e');
    }
  }

  Future<void> _removeCollaborator(int userId) async {
    try {
      await _service.removeCollaborator(widget.captureId, userId);
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Removed');
      await _loadCapture();
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Failed to remove: $e');
    }
  }

  Future<void> _toggleRosterItem(int index) async {
    if (index < 0 || index >= _roster.length) return;
    setState(() {
      final item = _roster[index];
      // Convert int (0/1) from database to bool
      final currentPresent = (item['present'] == 1 || item['present'] == true);
      item['present'] = !currentPresent;
      if (item['present']) {
        item['time'] = DateTime.now().toIso8601String();
        item['status'] = 'On Time';
      } else {
        item['time'] = null;
        item['status'] = 'Absent';
      }
      _isDirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture Session')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_capture == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Capture Session')),
        body: const Center(child: Text('Failed to load capture')),
      );
    }

    final canEdit = _userRole == 'owner' || _userRole == 'editor';

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isDirty) {
          final save = await _promptSaveIfDirty();
          if (save == true) {
            await _saveChanges();
          }
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: Container(
              decoration: BoxDecoration(gradient: AppGradients.of(context))),
          title: const Text('Capture Session'),
          actions: [
            // allow collaborators to open the full Capture ID screen (camera + tagging)
            IconButton(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Open Capture UI',
              onPressed: () async {
                // open CaptureIdScreen with the current roster so the collaborator sees the same list
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CaptureIdScreen(
                    sessionId: 'shared-${widget.captureId}',
                    initialRoster: _roster,
                    initialSubject: _capture!['subject']?.toString(),
                    initialStartTime: _capture!['start_time']?.toString(),
                    initialEndTime: _capture!['end_time']?.toString(),
                    onRosterChanged: (newRoster) async {
                      if (!mounted) return;
                      setState(() {
                        _roster = newRoster;
                        _isDirty = true;
                      });
                      // attempt immediate save/sync to server
                      try {
                        AppNotifier.showLoading(context, message: 'Syncing...');
                        await _service.updateCapture(
                          widget.captureId,
                          subject: _capture!['subject'],
                          date: _capture!['date'],
                          startTime: _capture!['start_time'],
                          endTime: _capture!['end_time'],
                          roster: _roster,
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context); // close loading
                        AppNotifier.showSnack(context, 'Synced changes');
                        setState(() => _isDirty = false);
                      } catch (e) {
                        Navigator.pop(context); // close loading
                        AppNotifier.showSnack(context, 'Sync failed: $e');
                      }
                    },
                  ),
                ));
              },
            ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _isDirty ? _saveChanges : null,
              ),
          ],
        ),
        body: Column(
          children: [
            // Capture info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_capture!['subject'] ?? 'Untitled',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Code: ${_capture!['share_code']}'),
                          ),
                          const SizedBox(width: 16),
                          Text('Role: $_userRole'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Collaborators section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Collaborators',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (canEdit)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Invite'),
                      onPressed: _showInviteDialog,
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 120,
              child: _collaborators.isEmpty
                  ? const Center(child: Text('No collaborators yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _collaborators.length,
                      itemBuilder: (_, i) {
                        final c = _collaborators[i];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(c['name'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        Text(c['email'] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                      ],
                                    ),
                                  ),
                                  if (canEdit)
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                      onPressed: () =>
                                          _removeCollaborator(c['id'] as int),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Roster section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text('Attendance (${_roster.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                      'Present: ${_roster.where((r) => r['present'] ?? false).length}',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: _roster.isEmpty
                  ? const Center(child: Text('No roster yet'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _roster.length,
                      itemBuilder: (_, i) {
                        final r = _roster[i];
                        // Handle both bool and int (0/1) from database
                        final isPresent =
                            (r['present'] == 1 || r['present'] == true);
                        return CheckboxListTile(
                          title: Text(r['name'] ?? ''),
                          subtitle: Text(r['id'] ?? ''),
                          value: isPresent,
                          onChanged:
                              canEdit ? (_) => _toggleRosterItem(i) : null,
                          tileColor: isPresent
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.3)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
