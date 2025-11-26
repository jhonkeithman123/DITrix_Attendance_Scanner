import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'xlsx_importer.dart';

/// Utility that provides masterlist import and attendance export functions.
/// Returns saved file path on success, throws on failure.
class FileIOService {
  /// Normalize a full name and extract a probable last name.
  static String _extractLastName(String name) {
    final s = name.trim();
    if (s.isEmpty) return '';
    // If "Last, First" format
    if (s.contains(',') && s.split(',').first.trim().isNotEmpty) {
      return s.split(',').first.trim();
    }
    // Otherwise take the last token as last name (handles "First Middle Last")
    final parts = s.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.last.trim() : s;
  }

  /// Sort a list of maps ({'id','name',...}) by last name (case-insensitive).
  static List<Map<String, String>> sortByLastName(
      List<Map<String, String>> list) {
    final copied = List<Map<String, String>>.from(list);
    copied.sort((a, b) {
      final la = _extractLastName(a['name'] ?? '').toLowerCase();
      final lb = _extractLastName(b['name'] ?? '').toLowerCase();
      final cmp = la.compareTo(lb);
      if (cmp != 0) return cmp;
      // fallback to full name compare
      return (a['name'] ?? '')
          .toLowerCase()
          .compareTo((b['name'] ?? '').toLowerCase());
    });
    return copied;
  }

  /// Pick CSV masterlist and parse into list of {id, name}
  static Future<List<Map<String, String>>> pickMasterlistCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return [];

    final bytes = result.files.first.bytes;
    if (bytes == null) return [];
    final content = utf8.decode(bytes);
    final lines = LineSplitter()
        .convert(content)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];

    final headerLower = lines.first.toLowerCase();
    final parsed = <Map<String, String>>[];

    List<String> splitCsvLine(String line) {
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

    bool looksLikeId(String s) {
      if (s.isEmpty) return false;
      final hasDigit = s.contains(RegExp(r'\d'));
      final shortToken = s.length < 6;
      return hasDigit || shortToken;
    }

    if (headerLower.contains('id') && headerLower.contains('name')) {
      final headers =
          splitCsvLine(lines.first).map((h) => h.trim().toLowerCase()).toList();
      final idIdx = headers.indexWhere((h) => h.contains('id'));
      final nameIdx = headers.indexWhere((h) => h.contains('name'));
      if (idIdx == -1 || nameIdx == -1) return [];
      for (var i = 1; i < lines.length; i++) {
        final cols = splitCsvLine(lines[i]);
        final id = cols.length > idIdx ? cols[idIdx].trim() : '';
        final name = cols.length > nameIdx ? cols[nameIdx].trim() : '';
        if (id.isNotEmpty && name.isNotEmpty) {
          parsed.add({'id': id, 'name': name});
        }
      }
    } else {
      for (final l in lines) {
        final cols = splitCsvLine(l);
        if (cols.length >= 2) {
          final a = cols[0].trim();
          final b = cols[1].trim();
          final probableId = looksLikeId(a) ? a : (looksLikeId(b) ? b : a);
          final probableName = probableId == a ? b : a;
          if (probableId.isNotEmpty && probableName.isNotEmpty) {
            parsed.add({'id': probableId, 'name': probableName});
          }
        }
      }
    }
    return sortByLastName(parsed);
  }

  /// Pick XLSX/XLS masterlist and parse into list of {id, name}
  static Future<List<Map<String, String>>> pickMasterlistXlsx() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: false,
    );
    if (res == null || res.files.isEmpty) return [];
    final path = res.files.single.path;
    if (path == null) return [];
    final file = File(path);

    // parse sheets -> Map<sheetName, List<Map<String, dynamic>>>
    final parsedSheets = XlsxImporter.parse(file);
    if (parsedSheets.isEmpty) return [];

    // Use first sheet by default
    final rows = parsedSheets.entries.first.value;
    final parsed = <Map<String, String>>[];

    bool looksLikeId(String s) {
      if (s.isEmpty) return false;
      final hasDigit = s.contains(RegExp(r'\d'));
      final shortToken = s.length < 6;
      return hasDigit || shortToken;
    }

    for (final row in rows) {
      // row: Map<String, dynamic>
      String id = '';
      String name = '';

      // try to find common id/name columns
      String? idKey = row.keys.firstWhere(
          (k) =>
              k.toLowerCase().contains('id') || k.toLowerCase().contains('no'),
          orElse: () => '');
      String? nameKey = row.keys.firstWhere(
          (k) =>
              k.toLowerCase().contains('name') ||
              k.toLowerCase().contains('surname') ||
              k.toLowerCase().contains('last'),
          orElse: () => '');

      if (idKey != '' && row[idKey] != null) id = row[idKey].toString().trim();
      if (nameKey != '' && row[nameKey] != null) {
        name = row[nameKey].toString().trim();
      }

      // fallback to first two columns if needed
      if (id.isEmpty || name.isEmpty) {
        final values = row.values.map((v) => v?.toString() ?? '').toList();
        if (values.length >= 2) {
          final a = values[0].trim();
          final b = values[1].trim();
          final probableId = looksLikeId(a) ? a : (looksLikeId(b) ? b : a);
          final probableName = probableId == a ? b : a;
          id = id.isEmpty ? probableId : id;
          name = name.isEmpty ? probableName : name;
        }
      }

      if (id.isNotEmpty && name.isNotEmpty) {
        parsed.add({'id': id, 'name': name});
      }
    }

    return sortByLastName(parsed);
  }

  /// Export CSV. Returns saved file path.
  static Future<String> exportCsv({
    required List<Map<String, dynamic>> roster,
    required String subject,
    required String startTime,
    required String dismissTime,
  }) async {
    final csvLines = <String>[];
    csvLines.add(
        'Subject,Subject Time,Subject Dismiss,Student ID,Student Name,Time In,Status');
    final subjEscaped = subject.replaceAll('"', '""');
    final subjTimeEscaped = startTime.replaceAll('"', '""');
    final subjDismissEscaped = dismissTime.replaceAll('"', '""');

    for (final row in roster) {
      final idEscaped = (row['id']?.toString() ?? '').replaceAll('"', '""');
      final nameEscaped = (row['name']?.toString() ?? '').replaceAll('"', '""');
      final timeIn = row['time']?.toString() ?? '';
      final status = row['status']?.toString() ??
          (row['present'] == true ? 'Present' : 'Absent');
      csvLines.add(
          '"$subjEscaped","$subjTimeEscaped","$subjDismissEscaped","$idEscaped","$nameEscaped","$timeIn","$status"');
    }
    final csv = csvLines.join('\n');
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName =
        'attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.csv';

    // Try public Documents on Android
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
            throw Exception('Storage permission not granted');
          }
        }
        final publicDir =
            Directory('/storage/emulated/0/Documents/DITrix attendance');
        if (!await publicDir.exists()) await publicDir.create(recursive: true);
        final file = File('${publicDir.path}/$fileName');
        await file.writeAsString(csv, flush: true);
        return file.path;
      } catch (_) {
        // fall through to app documents fallback
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDir.path}/DITrix attendance');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);
    final fallback = File('${targetDir.path}/$fileName');
    await fallback.writeAsString(csv, flush: true);
    return fallback.path;
  }

  /// Export XLSX. Returns saved file path.
  static Future<String> exportXlsx({
    required List<Map<String, dynamic>> roster,
    required String subject,
    required String startTime,
    required String dismissTime,
  }) async {
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
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.wrapText = true;
    }

    String safeStr(Object? v) => v == null ? '' : v.toString();
    final maxLens = List<int>.filled(headers.length, 0);

    for (var r = 0; r < roster.length; r++) {
      final row = roster[r];
      final values = [
        subject,
        startTime,
        dismissTime,
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

    for (var c = 0; c < maxLens.length; c++) {
      final width = ((maxLens[c] + 5).clamp(10, 60)).toDouble();
      try {
        sheet.getRangeByIndex(1, c + 1).columnWidth = width;
      } catch (_) {}
    }

    List<int> bytes;
    try {
      bytes = workbook.saveAsStream();
    } finally {
      workbook.dispose();
    }

    if (bytes.isEmpty) throw Exception('XLSX generation produced empty file');

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName =
        'attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.xlsx';

    // Try public Documents on Android
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
            throw Exception('Storage permission not granted');
          }
        }
        final publicDir =
            Directory('/storage/emulated/0/Documents/DITrix attendance');
        if (!await publicDir.exists()) await publicDir.create(recursive: true);
        final file = File('${publicDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (_) {
        // fall through
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDir.path}/DITrix attendance');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);
    final fallback = File('${targetDir.path}/$fileName');
    await fallback.writeAsBytes(bytes, flush: true);
    return fallback.path;
  }
}
