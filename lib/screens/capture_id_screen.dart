// ignore_for_file: unused_field

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../scanner_service/scan.dart';
import '../services/file_io_service.dart';
import '../theme/app_theme.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import '../services/camera_focus_detector.dart';
import '../utils/app_notifier.dart';

class CaptureIdScreen extends StatefulWidget {
  final String sessionId;
  const CaptureIdScreen({super.key, required this.sessionId});

  @override
  State<CaptureIdScreen> createState() => _CaptureIdScreenState();
}

class _CaptureIdScreenState extends State<CaptureIdScreen>
    with WidgetsBindingObserver {
  final _sessionStore = SessionStore();
  Session? _session;

  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> roster = [];
  Map<String, dynamic>? _lastScan; // last OCR/parse result for debugging

  String subject = '';
  TimeOfDay classStartTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay classEndTime = const TimeOfDay(hour: 0, minute: 0);

  // Camera state
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _cameraEnabled = true; // Toggle for manual on/off

  // Focus detector (extracted to its own file)
  late final CameraFocusDetector _focusDetector;

  // Auto-capture / burst control
  final bool _autoCapture = false;
  final bool _burstMode = false;
  final int _burstCount = 3;
  bool _isCapturing = false; // guard to avoid overlapping captures
  DateTime? _lastAutoCaptureAt;
  final Duration _autoCaptureCooldown = const Duration(seconds: 2);

  /// Attempt an auto-capture. Uses existing _captureAndTag for processing.
  Future<void> _attemptAutoCapture() async {
    if (!_cameraEnabled || !_isCameraInitialized || _cameraController == null) {
      return;
    }
    if (_isCapturing) return;
    _isCapturing = true;
    try {
      _log(
          'attemptAutoCapture: starting. burst=$_burstMode count=$_burstCount');
      // Some camera plugin versions require stopping imageStream before takePicture
      var wasStreaming = false;
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
          wasStreaming = true;
          _log('stopped image stream before capture');
        }
      } catch (e) {
        _log('stopImageStream failed: $e');
      }

      if (_burstMode && _burstCount > 1) {
        for (var i = 0; i < _burstCount; i++) {
          // use the same capture pipeline you already have
          await _captureAndTag();
          // small spacing between burst captures
          await Future.delayed(const Duration(milliseconds: 250));
        }
      } else {
        await _captureAndTag();
      }

      // restart stream if we stopped it
      if (wasStreaming) {
        try {
          _cameraController!
              .startImageStream((img) => _focusDetector.handleImage(img));
          _log('restarted image stream after capture');
        } catch (e) {
          _log('restart image stream failed: $e');
        }
      }

      _lastAutoCaptureAt = DateTime.now();
    } catch (e) {
      _log('auto-capture failed: $e');
    } finally {
      _isCapturing = false;
    }
  }

  late final ScannerService _scanner;
  final List<String> _uiLogs = <String>[];
  bool _developerMode = false;
  bool _showLogs = false;
  void _log(String msg) {
    // Only collect/print logs in Developer Mode
    if (!_developerMode) return;
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final line = '[$h:$m:$s] $msg';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _uiLogs.add(line);
      if (_uiLogs.length > 300) {
        _uiLogs.removeRange(0, _uiLogs.length - 300);
      }
    });
  }

  static const int _defaultCutoffHour = 9;
  static const int _defaultCutoffMinute = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanner = ScannerService(onLog: _log);
    _loadPrefs();
    _loadSession();
    _initCamera();
    // create detector but don't reference camera here; it will be used after init
    _focusDetector = CameraFocusDetector(
      onFocus: () {
        // only trigger capture if auto-capture is enabled and camera is available
        if (_cameraEnabled && _isCameraInitialized && _autoCapture == true) {
          _attemptAutoCapture();
        }
      },
      varianceThreshold: 150.0,
      step: 20,
      cooldown: const Duration(seconds: 2),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save when app goes to background or is about to be terminated
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveSession(); // fire-and-forget (dispose/lifecycle can’t await)
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    // Best-effort final save (cannot await in dispose)
    _saveSession();
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _focusDetector.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _developerMode = prefs.getBool('developer_mode') ?? false;
      _showLogs = _developerMode; // only show logs when Dev Mode is on
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      CameraDescription cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController =
          CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      // start streaming frames into the extracted focus detector
      try {
        _cameraController!
            .startImageStream((img) => _focusDetector.handleImage(img));
      } catch (_) {
        // some devices/plugins don't support simultaneous stream+takePicture
      }
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      _log('Camera init error: $e');
    }
  }

  Future<void> _toggleCamera() async {
    if (!_cameraEnabled) {
      if (_cameraController == null || !_isCameraInitialized) {
        await _initCamera();
        return;
      }
      try {
        await _cameraController!.resumePreview();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _cameraEnabled = true);
    } else {
      try {
        await _cameraController?.pausePreview();
      } catch (_) {
        await _cameraController?.dispose();
        _cameraController = null;
        _isCameraInitialized = false;
      }
      if (!mounted) return;
      setState(() => _cameraEnabled = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select attendance date',
    );
    if (!mounted) return;
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _loadSession() async {
    final s = await _sessionStore.load(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = s ?? Session(id: widget.sessionId, createdAt: DateTime.now());
      subject = _session!.subject;
      // Parse "HH:mm"
      TimeOfDay parse(String hhmm) {
        if (hhmm.isEmpty || !hhmm.contains(':')) {
          return const TimeOfDay(hour: 0, minute: 0);
        }
        final parts = hhmm.split(':');
        return TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0);
      }

      classStartTime = parse(_session!.startTime);
      classEndTime = parse(_session!.endTime);
      roster = List<Map<String, dynamic>>.from(_session!.roster);
    });
  }

  Future<void> _saveSession() async {
    if (_session == null) return;
    String toHHMM(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    _session!
      ..subject = subject
      ..startTime = toHHMM(classStartTime)
      ..endTime = toHHMM(classEndTime)
      ..roster = roster;
    await _sessionStore.save(_session!);
    _log('[SESSION] saved ${_session!.id}');
  }

  Future<void> _promptSubjectAndTime() async {
    final subjectCtrl = TextEditingController(text: subject);
    TimeOfDay tempStart = classStartTime;
    TimeOfDay tempEnd = classEndTime;
    bool devTemp = _developerMode;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set subject and class times'),
        content: StatefulBuilder(
          builder: (c, setStateDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Class start:'),
                  const SizedBox(width: 12),
                  TextButton(
                    child: Text(tempStart.format(c)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: c,
                        initialTime: tempStart,
                      );
                      if (picked != null) {
                        setStateDialog(() => tempStart = picked);
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Class dismiss:'),
                  const SizedBox(width: 12),
                  TextButton(
                    child: Text(tempEnd.format(c)),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: c,
                        initialTime: tempEnd,
                      );
                      if (picked != null) {
                        setStateDialog(() => tempEnd = picked);
                      }
                    },
                  ),
                ],
              ),
              const Divider(height: 24),
              SwitchListTile(
                title: const Text('Developer mode'),
                subtitle:
                    const Text('Enable in-app debug logs and diagnostics'),
                value: devTemp,
                onChanged: (v) => setStateDialog(() => devTemp = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                subject = subjectCtrl.text.trim();
                classStartTime = tempStart;
                classEndTime = tempEnd;
                _developerMode = devTemp;
                // show logs only when Dev Mode is on
                _showLogs = _developerMode;
              });
              await _saveSession();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('developer_mode', _developerMode);
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // helper to apply parsed masterlist into roster (ensure sorted by last name)
  Future<void> _applyParsedMasterlist(List<Map<String, String>> parsed) async {
    if (parsed.isEmpty) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Empty masterlist');
      return;
    }
    if (!mounted) return;
    setState(() {
      roster = parsed
          .map((p) => {
                'id': p['id']!,
                'name': p['name']!,
                'present': false,
                'time': null,
                'status': null
              })
          .toList();
    });
    await _saveSession();
    if (!mounted) return;
    AppNotifier.showSnack(context, 'Loaded ${roster.length} students');
  }

  // load CSV directly (used by popup menu)
  Future<void> _loadMasterlistCsv() async {
    try {
      final parsed = await FileIOService.pickMasterlistCsv();
      await _applyParsedMasterlist(parsed);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'CSV load failed: $e');
    }
  }

  // load XLSX directly (used by popup menu)
  Future<void> _loadMasterlistXlsx() async {
    try {
      final parsed = await FileIOService.pickMasterlistXlsx();
      await _applyParsedMasterlist(parsed);
    } catch (e) {
      if (!mounted) return;
      AppNotifier.showSnack(context, 'XLSX load failed: $e');
    }
  }

  void _simulateCaptureOne() {
    final idx = roster.indexWhere((r) => r['present'] == false);
    if (idx != -1) {
      final now = DateTime.now();
      setState(() {
        roster[idx]['present'] = true;
        roster[idx]['time'] = now.toIso8601String();
        roster[idx]['status'] = _computeStatus(now);
      });
      if (mounted) {
        AppNotifier.showSnack(context,
            'Marked "${roster[idx]['name']}" present (simulated) - ${roster[idx]['status']}');
      }
    } else {
      if (mounted) {
        AppNotifier.showSnack(context, 'All names already marked present');
      }
    }
  }

  String _computeStatus(DateTime time) {
    // use selected classStartTime as cutoff (local)
    final cutoff = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, classStartTime.hour, classStartTime.minute);
    final localTime = time.toLocal();
    return localTime.isBefore(cutoff) || localTime.isAtSameMomentAs(cutoff)
        ? 'On Time'
        : 'Late';
  }

  String _formatTimeIso(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return dt.toString().split('.').first;
    } catch (_) {
      return iso;
    }
  }

  Future<void> _captureAndTag() async {
    // Require subject and class times to be set before capturing
    final missingSubject = subject.trim().isEmpty;
    final missingStart =
        (classStartTime.hour == 0 && classStartTime.minute == 0);
    final missingEnd = (classEndTime.hour == 0 && classEndTime.minute == 0);
    if (missingSubject || missingStart || missingEnd) {
      if (!mounted) return;
      final doSet = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Set subject and times'),
          content: const Text(
              'Please set the Subject, Class start and Class dismiss times before capturing IDs.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Later')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Set now')),
          ],
        ),
      );
      if (doSet == true) {
        await _promptSubjectAndTime();
      }
      return;
    }

    if (!_cameraEnabled || !_isCameraInitialized || _cameraController == null) {
      if (mounted) {
        AppNotifier.showSnack(context, 'Camera not available');
      }
      return;
    }

    try {
      final file = await _cameraController!.takePicture();

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final saved = await File(file.path).copy('${dir.path}/capture_$ts.jpg');

      // clean image (resize/re-encode) and upload to backend; use cleaned file for tagging UI
      File imageToUse = saved;
      Map<String, dynamic>? scanResult;
      try {
        final res = await _cleanAndUploadImage(
            saved); // returns {'file': File, 'scan': Map}
        imageToUse = res['file'] as File? ?? saved;
        scanResult = res['scan'] as Map<String, dynamic>?;
      } catch (e) {
        _log('Image clean/upload failed: $e');
      }

      // always store lastScan for UI debug, even if empty
      setState(() {
        _lastScan = (scanResult ?? <String, dynamic>{});
      });

      // visible quick feedback so you always see result on-screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final id = (_lastScan?['student_number'] ?? '').toString();
        final name = (_lastScan?['surname'] ?? '').toString();
        AppNotifier.showSnack(
            context,
            id.isEmpty && name.isEmpty
                ? 'OCR empty'
                : 'OCR -> id=$id name=$name',
            duration: const Duration(seconds: 3));
        // dev-only verbose log
        _log('[OCR PREVIEW] ${(_lastScan?['analyzed'] ?? '').toString()}');
      });

      // dev-only verbose logs
      _log('[capture] saved=${saved.path} exists=${await saved.exists()}');
      _log(
          '[capture] cleaned=${imageToUse.path} size=${await imageToUse.length()}');
      _log('[capture] scanResult=${jsonEncode(_lastScan)}');

      // if OCR returned scan data, try to auto-match and mark attendance
      if (scanResult != null && scanResult.isNotEmpty) {
        setState(() {
          _lastScan = scanResult;
        });
        _log('[_captureAndTag] scanResult: ${jsonEncode(scanResult)}');
        final scannedNumber = (scanResult['student_number'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        final scannedSurname =
            (scanResult['surname'] ?? scanResult['analyzed'] ?? '')
                .toString()
                .toLowerCase()
                .trim();

        // 1) If student number exists on OCR, prefer exact id match
        if (scannedNumber.isNotEmpty) {
          final normScanId = _normalizeId(scannedNumber);
          final idIdx = roster.indexWhere(
              (r) => _normalizeId((r['id'] ?? '').toString()) == normScanId);

          if (idIdx != -1) {
            final now = DateTime.now();
            final status = _computeStatus(now);
            if (!mounted) return;
            setState(() {
              roster[idIdx]['present'] = true;
              roster[idIdx]['time'] = now.toIso8601String();
              roster[idIdx]['status'] = status;
            });
            AppNotifier.showSnack(context,
                'Auto-matched "${roster[idIdx]['name']}" by ID ($status)');
            return; // matched by ID, done
          }

          // id not found: ask user if this ID belongs to the class (offer to add & mark)
          final add = await showDialog<bool>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Unknown ID'),
              content: Text(
                  'Scanned student ID "$scannedNumber" was not found in the loaded masterlist. Add to class and mark present?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('No')),
                ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Yes, add & mark')),
              ],
            ),
          );

          if (add == true) {
            final now = DateTime.now();
            final status = _computeStatus(now);
            final displayName = scannedSurname.isNotEmpty
                ? scannedSurname.split(RegExp(r'\s+')).map((s) {
                    // capitalize simple surname token
                    return s.isEmpty
                        ? s
                        : '${s[0].toUpperCase()}${s.substring(1)}';
                  }).join(' ')
                : scannedNumber;
            if (!mounted) return;
            setState(() {
              roster.add({
                'id': scannedNumber,
                'name': displayName,
                'present': true,
                'time': now.toIso8601String(),
                'status': status
              });
            });
            AppNotifier.showSnack(
                context, 'Added $displayName and marked present ($status)');
            return;
          }
          // if user chose not to add, fall through to manual tagging UI
        }

        // 2) If scanned number absent or user declined add, try surname-only matching automatically
        if (scannedSurname.isNotEmpty) {
          double bestScore = 0.0;
          int bestIdx = -1;
          for (var entry in roster.asMap().entries) {
            final idx = entry.key;
            final rosterSurname =
                _extractSurnameFromName((entry.value['name'] ?? '').toString());
            final score = _nameSimilarity(rosterSurname, scannedSurname);
            if (score > bestScore) {
              bestScore = score;
              bestIdx = idx;
            }
          }
          const double threshold =
              0.65; // increase strictness for name-only match
          if (bestIdx != -1 && bestScore >= threshold) {
            final now = DateTime.now();
            final status = _computeStatus(now);
            if (!mounted) return;
            setState(() {
              roster[bestIdx]['present'] = true;
              roster[bestIdx]['time'] = now.toIso8601String();
              roster[bestIdx]['status'] = status;
            });
            AppNotifier.showSnack(context,
                'Auto-matched "${roster[bestIdx]['name']}" by name ($status)');
            return; // matched by name, done
          }
        }
      } else {
        _log('[_captureAndTag] no scan result');
      }

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _TaggingSheet(
          roster: roster,
          onTag: (index) {
            if (!mounted) return;
            final now = DateTime.now();
            final status = _computeStatus(now);
            setState(() {
              roster[index]['present'] = true;
              roster[index]['time'] = now.toIso8601String();
              roster[index]['status'] = status;
            });
            Navigator.of(ctx).pop();
            AppNotifier.showSnack(
                context, 'Marked "${roster[index]['name']}" present ($status)');
          },
          imageFile: imageToUse,
        ),
      );
    } catch (e) {
      _log('Capture error: $e');
      if (mounted) {
        AppNotifier.showSnack(context, 'Capture failed');
      }
    }
  }

  // simple name similarity based on common letters and length
  double _nameSimilarity(String a, String b) {
    final sa = a.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final sb = b.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (sa.isEmpty || sb.isEmpty) return 0.0;
    final setA = sa.split('').toSet();
    final setB = sb.split('').toSet();
    final common = setA.intersection(setB).length;
    final denom = max(sa.length, sb.length);
    double base = common / denom;
    // boost if one contains the other
    if (sa.contains(sb) || sb.contains(sa)) base = 1.0;
    return base;
  }

  Future<Map<String, dynamic>> _cleanAndUploadImage(File original) async {
    try {
      // Delegate OCR; dev-only log
      _log('[OCR] delegating to engine: ${original.path}');
      _log('[OCR] running on: ${Platform.operatingSystem} (${original.path})');
      final scanJson = await _scanner.runOcr(original);

      // Mobile hint
      if (scanJson['error'] == 'mobile_unsupported') {
        if (mounted) {
          AppNotifier.showSnack(context,
              'Python OCR isn\'t available on Android/iOS. Run on desktop or set up remote OCR.');
        }
        return {'file': original, 'scan': <String, dynamic>{}};
      }

      // Surface result immediately
      if (mounted) {
        final id = (scanJson['student_number'] ?? '').toString();
        final name = (scanJson['surname'] ?? '').toString();
        AppNotifier.showSnack(
            context,
            id.isEmpty && name.isEmpty
                ? 'OCR: empty'
                : 'OCR -> id=$id name=$name',
            duration: const Duration(seconds: 3));
        _log('[OCR DEBUG] result -> id="$id" name="$name"');
      }

      await _saveSession();
      return {'file': original, 'scan': scanJson};
    } catch (e) {
      _log('[OCR] error: $e');
      return {'file': original, 'scan': <String, dynamic>{}};
    }
  }

  Future<void> _copyLogs() async {
    final text = _uiLogs.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppNotifier.showSnack(context, 'Copied ${_uiLogs.length} log lines');
  }

  String _normalizeId(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // helper to extract surname from roster name (handles "Surname, First" and "First Last")
  String _extractSurnameFromName(String name) {
    final n = name.trim();
    if (n.contains(',')) {
      return n.split(',')[0].trim().toLowerCase();
    }
    final parts = n.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last.trim().toLowerCase() : n.toLowerCase();
  }

  Future<void> _exportCsv() async {
    try {
      if (roster.isEmpty) {
        if (mounted) {
          AppNotifier.showSnack(
              context, 'Roster empty - load a masterlist or add names first');
        }
        return;
      }
      if (subject.trim().isEmpty ||
          (classStartTime.hour == 0 && classStartTime.minute == 0) ||
          (classEndTime.hour == 0 && classEndTime.minute == 0)) {
        if (mounted) {
          AppNotifier.showSnack(
              context, 'Please set Subject and Subject Time before exporting');
        }
        return;
      }
      final path = await FileIOService.exportCsv(
        roster: roster,
        subject: subject,
        startTime: classStartTime.format(context),
        dismissTime: classEndTime.format(context),
      );
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Exported CSV to $path');
    } catch (e) {
      _log('CSV export failed: $e');
      if (mounted) {
        AppNotifier.showSnack(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _exportPrompt() async {
    final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
              title: const Text('Export format'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop('csv'),
                  child: const Text('Export CSV (no column widths)'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop('xlsx'),
                  child: const Text('Export XLSX (preserve widths & wrap)'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
              ],
            ));

    if (choice == 'csv') {
      await _exportCsv();
    }
    if (choice == 'xlsx') {
      await _exportXlsx();
    }
  }

  Future<void> _exportXlsx() async {
    try {
      final path = await FileIOService.exportXlsx(
        roster: roster,
        subject: subject,
        startTime: classStartTime.format(context),
        dismissTime: classEndTime.format(context),
      );
      if (!mounted) return;
      AppNotifier.showSnack(context, 'Exported XLSX to $path');
    } catch (e) {
      _log('XLSX export failed: $e');
      if (mounted) {
        AppNotifier.showSnack(context, 'Export failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppGradients.of(context)),
        ),
        title: const Text('Capture ID'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'clearLogs':
                  setState(() => _uiLogs.clear());
                  break;
                case 'copyLogs':
                  await _copyLogs();
                  break;
                case 'settings':
                  await _promptSubjectAndTime();
                  break;
                case 'toggleCam':
                  await _toggleCamera();
                  break;
                case 'loadCsv':
                  await _loadMasterlistCsv();
                  break;
                case 'loadXlsx':
                  await _loadMasterlistXlsx();
                  break;
                case 'export':
                  await _exportPrompt();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'settings',
                child: Text('Set subject & class time'),
              ),
              PopupMenuItem(
                value: 'toggleCam',
                child:
                    Text(_cameraEnabled ? 'Disable camera' : 'Enable camera'),
              ),
              const PopupMenuItem(
                value: 'loadCsv',
                child: Text('Load masterlist (CSV)'),
              ),
              const PopupMenuItem(
                value: 'loadXlsx',
                child: Text('Load masterlist (XLSX)'),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text('Export attendance'),
              ),
              if (_developerMode)
                const PopupMenuItem(enabled: false, child: Divider(height: 1)),
              if (_developerMode)
                const PopupMenuItem(
                  value: 'clearLogs',
                  child: Text('Clear debug logs'),
                ),
              if (_developerMode)
                const PopupMenuItem(
                  value: 'copyLogs',
                  child: Text('Copy debug logs'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Compact session info card: subject, date, start & dismiss as chips
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject.isEmpty ? 'No subject' : subject,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _InfoChip(
                                        icon: Icons.calendar_today,
                                        label: selectedDate
                                            .toLocal()
                                            .toIso8601String()
                                            .split("T")
                                            .first),
                                    const SizedBox(width: 8),
                                    _InfoChip(
                                        icon: Icons.play_arrow,
                                        label: classStartTime.format(context)),
                                    const SizedBox(width: 8),
                                    _InfoChip(
                                        icon: Icons.stop,
                                        label: classEndTime.format(context)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: _promptSubjectAndTime,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Date'),
                ),
              ],
            ),
          ),
          Container(
            height: 240,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black12,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (_cameraEnabled &&
                      _isCameraInitialized &&
                      _cameraController != null)
                  ? CameraPreview(_cameraController!)
                  : const Center(child: Text('Camera disabled')),
            ),
          ),
          if (_developerMode && _showLogs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Row(
                        children: [
                          const Text('Debug logs',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _copyLogs,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copy'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _uiLogs.length,
                        itemBuilder: (ctx, i) => Text(
                          _uiLogs[i],
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
              child: roster.isEmpty
                  ? const Center(
                      child: Text('Load the masterlist to show the list'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: roster.length,
                      itemBuilder: (context, i) {
                        final e = roster[i];
                        final name = (e['name'] ?? '') as String;
                        final id = (e['id'] ?? '') as String;
                        final timeStr = _formatTimeIso(e['time']);
                        final status = (e['status'] ??
                                (e['present'] == true ? 'Present' : 'Absent'))
                            as String;
                        Color chipColor;
                        switch (status) {
                          case 'On Time':
                            chipColor = Colors.green;
                            break;
                          case 'Late':
                            chipColor = Colors.orange;
                            break;
                          case 'Present':
                            chipColor = Colors.blue;
                            break;
                          default:
                            chipColor = Colors.grey;
                        }
                        String initials() {
                          final parts = name.trim().split(RegExp(r'\s+'));
                          if (parts.isEmpty) return '?';
                          final a =
                              parts.first.isNotEmpty ? parts.first[0] : '';
                          final b = parts.length > 1 && parts.last.isNotEmpty
                              ? parts.last[0]
                              : '';
                          return (a + b).toUpperCase();
                        }

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  child: Text(initials()),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: chipColor.withValues(
                                                  alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            child: Text(
                                              status,
                                              style: TextStyle(
                                                color: chipColor,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.badge,
                                              size: 16,
                                              color:
                                                  Theme.of(context).hintColor),
                                          const SizedBox(width: 6),
                                          Expanded(
                                              child: Text(id,
                                                  style: TextStyle(
                                                      color: Theme.of(context)
                                                          .hintColor))),
                                          const SizedBox(width: 12),
                                          Icon(Icons.access_time,
                                              size: 16,
                                              color:
                                                  Theme.of(context).hintColor),
                                          const SizedBox(width: 6),
                                          Text(timeStr.isEmpty ? '—' : timeStr,
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .hintColor)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Switch(
                                  value: e['present'] ?? false,
                                  onChanged: (v) async {
                                    setState(() {
                                      roster[i]['present'] = v;
                                      if (!v) {
                                        roster[i]['time'] = null;
                                        roster[i]['status'] = null;
                                      } else {
                                        final now = DateTime.now();
                                        roster[i]['time'] =
                                            now.toIso8601String();
                                        roster[i]['status'] =
                                            _computeStatus(now);
                                      }
                                    });
                                    await _saveSession();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('capture'),
                    onPressed: _captureAndTag,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera), // simulate
                  label: const Text('Simulate'),
                  onPressed: _simulateCaptureOne,
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Export'),
                  onPressed: _exportPrompt,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// bottom sheet widget for tagging a captured image to a name
class _TaggingSheet extends StatefulWidget {
  final List<Map<String, dynamic>> roster;
  final void Function(int index) onTag;
  final File imageFile;

  //ignore: use_super_parameters
  const _TaggingSheet({
    required this.roster,
    required this.onTag,
    required this.imageFile,
    Key? key,
  }) : super(key: key);

  @override
  State<_TaggingSheet> createState() => _TaggingSheetState();
}

class _TaggingSheetState extends State<_TaggingSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    // no search input — show full roster for tagging (auto-match occurs before sheet shows)
    final filtered = widget.roster.asMap().entries.toList();

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // image preview + search
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Select student to tag'),
                      SizedBox(height: 6),
                      Text(
                          'If auto-match succeeded the person is already marked.'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(widget.imageFile, fit: BoxFit.cover),
                  ),
                ),
              ]),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 280,
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) {
                  final pair = filtered[i];
                  final idx = pair.key;
                  final entry = pair.value;
                  return ListTile(
                    title: Text(entry['name']),
                    trailing: entry['present']
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => widget.onTag(idx),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// simple bottom sheet to confirm among multiple surname candidates
// ignore: unused_element
class _ConfirmMatchesSheet extends StatelessWidget {
  final List<MapEntry<int, Map<String, dynamic>>> matches;
  // ignore: use_super_parameters
  const _ConfirmMatchesSheet(this.matches, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Select matching student')),
          ...matches.map((e) {
            final idx = e.key;
            final entry = e.value;
            return ListTile(
              title: Text(entry['name'] ?? ''),
              subtitle: Text('ID: ${entry['id'] ?? ''}'),
              onTap: () => Navigator.of(context).pop(idx),
            );
          }),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'))
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
