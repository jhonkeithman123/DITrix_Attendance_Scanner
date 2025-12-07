import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'xlsx_importer.dart';
import 'docx_importer.dart';
import 'pdf_importer.dart';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

  static Future<List<Map<String, String>>> pickMasterlistDocx() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    if (res == null || res.files.isEmpty || res.files.first.path == null) {
      throw Exception('No DOCX selected');
    }

    final file = File(res.files.first.path!);
    final parsed = DocxImporter.parseMasterlist(file);
    if (parsed.isEmpty) throw Exception('No rows found in DOCX');
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

  static Future<List<Map<String, String>>> pickMasterlistPdf() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (res == null || res.files.isEmpty || res.files.first.path == null) {
      throw Exception('No PDF selected');
    }
    final file = File(res.files.first.path!);
    final rows = await PdfImporter.parseMasterlist(file);
    // sort (reuse by last-name heuristic)
    return sortByLastName(rows);
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

  /// Export DOCX without a template. Creates a simple table with headers and rows.
  /// Returns saved file path.
  static Future<String> exportDocx({
    required List<Map<String, dynamic>> roster,
    required String subject,
    required String startTime,
    required String dismissTime,
  }) async {
    // Build wordprocessingML for a minimal document with one table.
    String xmlEscape(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    String textRun(String text) {
      final safe = xmlEscape(text);
      return '<w:r><w:t>$safe</w:t></w:r>';
    }

    String tableCell(String text) {
      return '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr><w:p>${textRun(text)}</w:p></w:tc>';
    }

    // Header row
    final headers = [
      'Subject',
      'Subject Time',
      'Subject Dismiss',
      'Student ID',
      'Student Name',
      'Time In',
      'Status'
    ];
    final headerRow = '<w:tr>${headers.map((h) => tableCell(h)).join()}</w:tr>';

    // Data rows
    String safeStr(Object? v) => v == null ? '' : v.toString();
    final rowsXml = StringBuffer();

    for (final row in roster) {
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
      rowsXml.write('<w:tr>');
      for (final v in values) {
        rowsXml.write(tableCell(v));
      }
      rowsXml.write('</w:tr>');
    }

    final bodyXml = '''
  <w:body>
  <w:p><w:r><w:t>Attendance</w:t></w:r></w:p>
  <w:tbl>
    <w:tblPr>
      <w:tblW w:w="0" w:type="auto"/>
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>
        <w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>
        <w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>
        <w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
      </w:tblBorders>
    </w:tblPr>
    $headerRow
    ${rowsXml.toString()}
  </w:tbl>
  <w:sectPr/>
</w:body>
    ''';

    final docXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
$bodyXml
</w:document>
''';

    // Build DOCX (ZIP) with required parts
    final archive = Archive();

    // [Content_Types].xml
    const contentTypes = '''
<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

    // _rels/.rels
    const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';

    // word/_rels/document.xml.rels (empty minimal)
    const docRels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>
''';

    archive.addFile(ArchiveFile('[Content_Types].xml',
        utf8.encode(contentTypes).length, utf8.encode(contentTypes)));
    archive.addFile(ArchiveFile(
        '_rels/.rels', utf8.encode(rels).length, utf8.encode(rels)));
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels',
        utf8.encode(docRels).length, utf8.encode(docRels)));
    archive.addFile(ArchiveFile(
        'word/document.xml', utf8.encode(docXml).length, utf8.encode(docXml)));

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('DOCX generation failed');
    }

    // Save to Android public Documents
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName =
        'attendance_${subject.isNotEmpty ? "${subject.replaceAll(RegExp(r'[^\w\-]'), '_')}_" : ""}$ts.docx';

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
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final file = File('${publicDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (_) {
        // fall through to app documents
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDir.path}/DITrix attendance');
    if (!await targetDir.exists()) await targetDir.create(recursive: true);
    final fallback = File('${targetDir.path}/$fileName');
    await fallback.writeAsBytes(bytes, flush: true);
    return fallback.path;
  }

  /// Export PDF to Android Documents (falls back to app docs). Two-column layout.
  static Future<String> exportPdf({
    required List<Map<String, dynamic>> roster,
    required String subject,
    required String startTime,
    required String dismissTime,
  }) async {
    final pdf = pw.Document();
    final headerStyle =
        pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
    final labelStyle = pw.TextStyle(fontSize: 11, color: PdfColors.grey700);
    final cellStyle = pw.TextStyle(fontSize: 11);

    // Build a simple table: ID | Name | Present | Time | Status
    pw.Widget buildHeader() => pw.Column(children: [
          pw.Text('Attendance', style: headerStyle),
          pw.SizedBox(height: 6),
          pw.Row(children: [
            pw.Expanded(child: pw.Text('Subject: $subject', style: labelStyle)),
            pw.SizedBox(width: 12),
            pw.Text('Start: $startTime', style: labelStyle),
            pw.SizedBox(width: 12),
            pw.Text('Dismiss: $dismissTime', style: labelStyle),
          ]),
          pw.SizedBox(height: 12),
        ]);

    pw.TableRow buildHeaderRow() => pw.TableRow(children: [
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Student ID', style: headerStyle)),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Name', style: headerStyle)),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Present', style: headerStyle)),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Time', style: headerStyle)),
          pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Status', style: headerStyle)),
        ]);

    List<pw.TableRow> buildRows() => roster.map((e) {
          final id = (e['id'] ?? '').toString();
          final name = (e['name'] ?? '').toString();
          final present = e['present'] == true ? 'Yes' : 'No';
          final time = (e['time'] ?? '').toString();
          final status =
              (e['status'] ?? (e['present'] == true ? 'Present' : 'Absent'))
                  .toString();
          return pw.TableRow(children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(id, style: cellStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(name, style: cellStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(present, style: cellStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(time, style: cellStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(status, style: cellStyle)),
          ]);
        }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(24),
        ),
        build: (context) => [
          buildHeader(),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            columnWidths: {
              0: const pw.FixedColumnWidth(120),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(120),
              4: const pw.FixedColumnWidth(80),
            },
            children: [
              buildHeaderRow(),
              ...buildRows(),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    // Same save logic as other exports
    Directory outDir;
    try {
      PermissionStatus status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.request();
      }
      if (!status.isGranted) {
        final s2 = await Permission.storage.request();
        if (!s2.isGranted) {
          throw Exception('Storage permission not granted');
        }
      }
      outDir = Directory('/storage/emulated/0/Documents/DITrix attendance');
      if (!await outDir.exists()) await outDir.create(recursive: true);
    } catch (_) {
      final docs = await getApplicationDocumentsDirectory();
      outDir = Directory('${docs.path}/DITrix attendance');
      if (!await outDir.exists()) await outDir.create(recursive: true);
    }
    final ts =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final out = File('${outDir.path}/attendance_$ts.pdf');
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }
}
