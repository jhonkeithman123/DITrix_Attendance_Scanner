import 'dart:io';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CaptureIdScreen extends StatefulWidget {
  const CaptureIdScreen({super.key});

  @override
  State<CaptureIdScreen> createState() => _CaptureIdScreenState();
}

class _CaptureIdScreenState extends State<CaptureIdScreen> {
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> roster = [];

  // Camera state
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

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

  Future<void> _loadMasterlist() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (result == null) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final content = utf8.decode(bytes);
    final lines = LineSplitter().convert(content);
    final names =
        lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toSet().toList();

    setState(() {
      roster = names.map((n) => {'name': n, 'present': false}).toList();
    });
  }

  void _loadSampleMasterlist() {
    const sample = [
      'Alice Johnson',
      'Bob Smith',
      'Carol Lee',
      'Daniel Kim',
      'Eve Martinez',
    ];
    setState(() {
      roster = sample.map((n) => {'name': n, 'present': false}).toList();
    });
  }

  void _simulateCaptureOne() {
    final idx = roster.indexWhere((r) => r['present'] == false);
    if (idx != -1) {
      setState(() => roster[idx]['present'] = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Marked "${roster[idx]['name']}" present (simulated)')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All names already marked present')));
    }
  }

  Future<void> _captureAndTag() async {
    if (!_isCameraInitialized || _cameraController == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Camera not available')));
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
            setState(() => roster[index]['present'] = true);
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Marked "${roster[index]['name']}" present')),
            );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Roster empty - load a masterlist or add names first')),
        );
      }
      return;
    }

    final csvLines = <String>[];
    csvLines.add('Date,Name,Present');
    final dateStr = selectedDate.toIso8601String().split('T').first;
    for (final row in roster) {
      final present = (row['present'] == true) ? 'Present' : 'Absent';
      final nameEscaped = row['name'].toString().replaceAll('"', '""');
      csvLines.add('$dateStr,"$nameEscaped",$present');
    }
    final csv = csvLines.join('\n');

    String ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    try {
      // try external Documents folder first (best-effort)
      final extDirs =
          await getExternalStorageDirectories(type: StorageDirectory.documents);
      Directory targetDir;
      if (extDirs != null && extDirs.isNotEmpty) {
        targetDir = Directory('${extDirs.first.path}/DITrix attendance');
      } else {
        // fallback to app documents
        final appDir = await getApplicationDocumentsDirectory();
        targetDir = Directory('${appDir.path}/DITrix attendance');
      }

      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final file = File('${targetDir.path}/attendance_$ts.csv');
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported CSV to ${file.path}')),
      );
    } catch (e) {
      // final fallback to app documents
      final appDir = await getApplicationDocumentsDirectory();
      final fallback = File('${appDir.path}/attendance_$ts.csv');
      await fallback.writeAsString(csv, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported CSV to ${fallback.path} (fallback)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture ID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Load masterlist (CSV Excel file)',
            onPressed: _loadMasterlist,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export attendance (CSV Excel file)',
            onPressed: _exportCsv,
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
                    'Date: ${selectedDate.toLocal().toIso8601String().split("T").first}',
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
              child: _isCameraInitialized && _cameraController != null
                  ? CameraPreview(_cameraController!)
                  : const Center(child: Text('Camera initializing...')),
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
                        return ListTile(
                          title: Text(entry['name'] ?? ''),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(entry['present'] ? 'Present' : 'Absent',
                                style: TextStyle(
                                    color: entry['present']
                                        ? Colors.greenAccent
                                        : Colors.redAccent)),
                            const SizedBox(width: 12),
                            Switch(
                              value: entry['present'] ?? false,
                              onChanged: (v) =>
                                  setState(() => roster[i]['present'] = v),
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
                    label: const Text('Capture & Tag'),
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
                  label: const Text('Export CSV'),
                  onPressed: _exportCsv,
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
