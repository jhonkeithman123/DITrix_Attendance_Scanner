// ignore_for_file: unused_field

import 'dart:io';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class CaptureIdScreen extends StatefulWidget {
  const CaptureIdScreen({super.key});

  @override
  State<CaptureIdScreen> createState() => _CaptureIdScreenState();
}

class _CaptureIdScreenState extends State<CaptureIdScreen> {
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> roster = [];

  String subject = '';
  TimeOfDay classStartTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay classEndTime = const TimeOfDay(hour: 0, minute: 0);

  // Camera state
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _cameraEnabled = true; // Toggle for manual on/off

  static const int _defaultCutoffHour = 9;
  static const int _defaultCutoffMinute = 0;

  @override
  void initState() {
    super.initState();
    _loadSampleMasterlist();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
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
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _promptSubjectAndTime() async {
    final subjectCtrl = TextEditingController(text: subject);
    TimeOfDay tempStart = classStartTime;
    TimeOfDay tempEnd = classEndTime;

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
                decoration:
                    const InputDecoration(labelText: 'Subject (e.g. Math)'),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                subject = subjectCtrl.text.trim();
                classStartTime = tempStart;
                classEndTime = tempEnd;
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMasterlist() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final content = utf8.decode(bytes);
    final lines = LineSplitter()
        .convert(content)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Empty masterlist')));
      }
      return;
    }

    final first = lines.first;
    List<Map<String, String>> parsed = [];

    final headerLower = first.toLowerCase();
    if (headerLower.contains('id') && headerLower.contains('name')) {
      final headers =
          _splitCsvLine(first).map((h) => h.trim().toLowerCase()).toList();
      final idIdx = headers.indexWhere((h) => h.contains('id'));
      final nameIdx = headers.indexWhere((h) => h.contains('name'));
      if (idIdx == -1 || nameIdx == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Masterlist header must include id and name')));
        }
        return;
      }

      for (var i = 1; i < lines.length; i++) {
        final cols = _splitCsvLine(lines[i]);
        final id = cols.length > idIdx ? cols[idIdx].trim() : '';
        final name = cols.length > nameIdx ? cols[nameIdx].trim() : '';
        if (id.isNotEmpty && name.isNotEmpty) {
          parsed.add({'id': id, 'name': name});
        }
      }
    } else {
      for (final l in lines) {
        final cols = _splitCsvLine(l);
        if (cols.length >= 2) {
          final a = cols[0].trim();
          final b = cols[1].trim();

          final probableId = _looksLikeId(a) ? a : (_looksLikeId(b) ? b : a);
          final probableName = probableId == a ? b : a;
          if (probableId.isNotEmpty && probableName.isNotEmpty) {
            parsed.add({'id': probableId, 'name': probableName});
          }
        }
      }
    }

    if (parsed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Masterlist must include student id and name (CSV)')));
      }
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

      // helper: pick surname from either "Surname, First ..." or "First ... Last"
      // ignore: no_leading_underscores_for_local_identifiers
      String _surnameKey(Map<String, dynamic> e) {
        final name = (e['name'] ?? '').toString().trim();
        if (name.isEmpty) return '';
        if (name.contains(',')) {
          // "Surname, First Middle" -> surname before comma
          return name.split(',')[0].trim().toLowerCase();
        }
        final parts = name.split(RegExp(r'\s+'));
        return parts.isNotEmpty ? parts.last.toLowerCase() : name.toLowerCase();
      }

      roster.sort((a, b) => _surnameKey(a).compareTo(_surnameKey(b)));
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded ${roster.length} students')));
    }
  }

  List<String> _splitCsvLine(String line) {
    final List<String> result = [];
    final buffer = StringBuffer();
    bool inQuote = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (ch == ',' && !inQuote) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  bool _looksLikeId(String s) {
    if (s.isEmpty) return false;

    final hasDigit = s.contains(RegExp(r'\d'));
    final shortToken = s.length < 6;
    return hasDigit || shortToken;
  }

  void _loadSampleMasterlist() {
    const sample = [
      {'id': 'S001', 'name': 'Alice Jhonson'},
      {'id': 'S002', 'name': 'Bob Smith'},
      {'id': 'S003', 'name': 'Carol Lee'},
      {'id': 'S004', 'name': 'Daniel Kim'},
      {'id': 'S005', 'name': 'Eve Martinez'},
    ];
    if (!mounted) return;
    setState(() {
      roster = sample
          .map((n) => {
                'id': n['id']!,
                'name': n['name']!,
                'present': false,
                'time': null,
                'status': null
              })
          .toList();
      roster.sort((a, b) {
        String surnameOf(String name) {
          final s = name.trim();
          if (s.contains(',')) return s.split(',')[0].trim().toLowerCase();
          final parts = s.split(RegExp(r'\s+'));
          return parts.isNotEmpty ? parts.last.toLowerCase() : s.toLowerCase();
        }

        return surnameOf(a['name'] as String)
            .compareTo(surnameOf(b['name'] as String));
      });
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Marked "${roster[idx]['name']}" present (simulated) - ${roster[idx]['status']}')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All names already marked present')));
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
    if (!_cameraEnabled || !_isCameraInitialized || _cameraController == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera not available')));
      }
      return;
    }

    try {
      final file = await _cameraController!.takePicture();

      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final saved = await File(file.path).copy('${dir.path}/capture_$ts.jpg');

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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    'Marked "${roster[index]['name']}" present ($status)')));
          },
          imageFile: saved,
        ),
      );
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Capture failed')));
      }
    }
  }

  Future<void> _exportCsv() async {
    if (roster.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Roster empty - load a masterlist or add names first')));
      }
      return;
    }

    if (subject.trim().isEmpty ||
        (classStartTime.hour == 0 && classStartTime.minute == 0) ||
        (classEndTime.hour == 0 && classEndTime.minute == 0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please set Subject and Subject Time before exporting'),
        ));
      }
      return;
    }

    final csvLines = <String>[];
    // include subject, subject time (class start), subject dismiss (end), then student data and time in
    csvLines.add(
        'Subject,Subject Time,Subject Dismiss,Student ID,Student Name,Time In,Status');
    final subjEscaped = subject.replaceAll('"', '""');
    final subjTimeEscaped =
        classStartTime.format(context).replaceAll('"', '""');
    final subjDismissEscaped =
        classEndTime.format(context).replaceAll('"', '""');
    for (final row in roster) {
      final idEscaped = row['id']?.toString().replaceAll('"', '""') ?? '';
      final nameEscaped = row['name']?.toString().replaceAll('"', '""') ?? '';
      final timeIn = row['time']?.toString() ?? '';
      final status = row['status']?.toString() ??
          (row['present'] == true ? 'Present' : 'Absent');
      csvLines.add(
          '"$subjEscaped","$subjTimeEscaped","$subjDismissEscaped","$idEscaped","$nameEscaped","$timeIn","$status"');
    }
    final csv = csvLines.join('\n');

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');

    // Try to write to public Documents (Android) first
    if (Platform.isAndroid) {
      try {
        // request manage external storage (Android 11+) or storage permission
        PermissionStatus manageStatus =
            await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          manageStatus = await Permission.manageExternalStorage.request();
        }
        if (!manageStatus.isGranted) {
          // fallback to legacy storage permission
          final storageStatus = await Permission.storage.request();
          if (!storageStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Storage permission required to export to Documents')));
            }
            return;
          }
        }

        final publicDir =
            Directory('/storage/emulated/0/Documents/DITrix attendance');
        if (!await publicDir.exists()) await publicDir.create(recursive: true);
        final file = File(
            '${publicDir.path}/attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.csv');
        await file.writeAsString(csv, flush: true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported CSV to ${file.path}')));
        return;
      } catch (e) {
        debugPrint('Public export failed: $e');
        // fall through to app-documents fallback
      }
    }

    // Final fallback: app documents folder
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/DITrix attendance');
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final fallback = File(
          '${targetDir.path}/attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.csv');
      await fallback.writeAsString(csv, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported CSV to ${fallback.path}')));
    } catch (e) {
      debugPrint('Final fallback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Export failed')));
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
    if (roster.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Roster empty - load a masterlist or add names first')));
      }
      return;
    }

    if (subject.trim().isEmpty ||
        (classStartTime.hour == 0 && classStartTime.minute == 0) ||
        (classEndTime.hour == 0 && classEndTime.minute == 0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please set Subject, Subject Time and Dismiss before exporting'),
        ));
      }
      return;
    }

    // create XLSX using syncfusion_flutter_xlsio so we can set column widths / wrap text
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Attendance';

    final headers = [
      'Subject',
      'Subject Time',
      'Subject Dismiss',
      'Student ID',
      'Student Name',
      'Time In',
      'Status'
    ];

    // header row (1-based indices)
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.wrapText = true;
      // small padding by increasing row height a bit
    }

    // rows and compute max length per column to set widths
    final maxLens = List<int>.filled(headers.length, 0);
    String safeStr(Object? v) => v == null ? '' : v.toString();

    final subj = subject;
    final subjTime = classStartTime.format(context);
    final subjDismiss = classEndTime.format(context);

    for (var r = 0; r < roster.length; r++) {
      final row = roster[r];
      final values = [
        subj,
        subjTime,
        subjDismiss,
        safeStr(row['id']),
        safeStr(row['name']),
        safeStr(row['time']),
        safeStr(
            row['status'] ?? (row['present'] == true ? 'Present' : 'Absent')),
      ];
      for (var c = 0; c < values.length; c++) {
        final v = values[c];
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        cell.setText(v);
        cell.cellStyle.wrapText = true;
        if (v.length > maxLens[c]) maxLens[c] = v.length;
      }
    }

    // set approximate column widths based on max text length
    for (var c = 0; c < maxLens.length; c++) {
      // Excel width units ≈ character count; add padding, clamp to sensible range
      final width = ((maxLens[c] + 5).clamp(10, 60)).toDouble();
      try {
        sheet.getRangeByIndex(1, c + 1).columnWidth = width;
      } catch (_) {}
    }

    // save workbook and handle errors — saveAsStream() returns a List<int>, not null
    List<int> bytes;
    try {
      bytes = workbook.saveAsStream();
    } catch (e, st) {
      workbook.dispose();
      debugPrint('XLSX save failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('XLSX export failed')));
      }
      return;
    }
    workbook.dispose();
    if (bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('XLSX export produced empty file')));
      }
      return;
    }

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName =
        'attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.xlsx';

    // write similar to CSV: try public Documents then app documents
    if (Platform.isAndroid) {
      try {
        PermissionStatus manageStatus =
            await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
          manageStatus = await Permission.manageExternalStorage.request();
        }
        if (!manageStatus.isGranted) {
          final storageStatus = await Permission.storage.request();
          if (!storageStatus.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Storage permission required to export XLSX')));
            }
            return;
          }
        }

        final publicDir =
            Directory('/storage/emulated/0/Documents/DITrix attendance');
        if (!await publicDir.exists()) await publicDir.create(recursive: true);
        final file = File('${publicDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported XLSX to ${file.path}')));
        return;
      } catch (e) {
        debugPrint('XLSX public export failed: $e');
      }
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory('${appDir.path}/DITrix attendance');
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final fallback = File('${targetDir.path}/$fileName');
      await fallback.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported XLSX to ${fallback.path}')));
    } catch (e) {
      debugPrint('XLSX final fallback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('XLSX export failed')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final primary = Theme.of(context).colorScheme.primary;
    // ignore: unused_local_variable
    final secondary = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture ID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Set subject & class time',
            onPressed: _promptSubjectAndTime,
          ),
          IconButton(
            icon: Icon(_cameraEnabled ? Icons.videocam : Icons.videocam_off),
            tooltip: _cameraEnabled ? 'Disable camera' : 'Enable camera',
            onPressed: _toggleCamera,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Load masterlist (CSV)',
            onPressed: _loadMasterlist,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export attendance',
            onPressed: _exportPrompt,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    subject.isEmpty
                        ? 'Date: ${selectedDate.toLocal().toIso8601String().split("T").first}'
                        : 'Subject: $subject  •  Date: ${selectedDate.toLocal().toIso8601String().split("T").first}  •  Start: ${classStartTime.format(context)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Choose date'),
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
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
              child: roster.isEmpty
                  ? const Center(child: Text('No names loaded'))
                  : ListView.separated(
                      itemCount: roster.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final entry = roster[i];
                        final timeStr = _formatTimeIso(entry['time']);
                        final status = entry['status'] ??
                            (entry['present'] == true ? 'Present' : 'Absent');
                        return ListTile(
                          title: Text(entry['name'] ?? ''),
                          subtitle: Text(
                              'ID: ${entry['id'] ?? ''}  •  Time: $timeStr'),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(status,
                                style: TextStyle(
                                    color: status == 'On Time' ||
                                            status == 'Present'
                                        ? Colors.greenAccent
                                        : Colors.redAccent)),
                            const SizedBox(width: 12),
                            Switch(
                              value: entry['present'] ?? false,
                              onChanged: (v) => setState(() {
                                roster[i]['present'] = v;
                                if (!v) {
                                  roster[i]['time'] = null;
                                  roster[i]['status'] = null;
                                } else {
                                  final now = DateTime.now();
                                  roster[i]['time'] = now.toIso8601String();
                                  roster[i]['status'] = _computeStatus(now);
                                }
                              }),
                            ),
                          ]),
                        );
                      })),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text(''),
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
    final filtered = widget.roster
        .asMap()
        .entries
        .where((e) => (e.value['name'] as String)
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();

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
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search name to tag',
                    ),
                    onChanged: (v) => setState(() => query = v),
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
