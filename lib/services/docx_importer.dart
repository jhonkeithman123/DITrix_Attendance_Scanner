import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;

//* Utility that is responsible for the importing of the docs file
class DocxImporter {
  ///* Parse a .docx file and extract rows with columns "id" and "name".
  ///* Supports word tables (preferred). Falls back to paragraphs with "ID Name" per line.
  static List<Map<String, String>> parseMasterlist(File file) {
    final bytes = file.readAsBytesSync();
    final zip = ZipDecoder().decodeBytes(bytes);
    final entry = zip.files.firstWhere(
      (f) => f.name.toLowerCase() == 'word/document.xml',
      orElse: () => throw Exception('Invalid DOCX: missing word.document.xml'),
    );
    final contentBytes = entry.content as List<int>;
    final docXml = utf8.decode(contentBytes);
    final doc = xml.XmlDocument.parse(docXml);

    //* Try tables first
    final rows = <Map<String, String>>[];
    bool gotFromTables = false;
    final tables = doc.findAllElements('tbl');
    for (final tbl in tables) {
      final trs = tbl.findAllElements('tr').toList();
      if (trs.isEmpty) continue;

      //* First row as header
      final headerCells = _cellsText(trs.first);
      if (headerCells.isEmpty) continue;

      final idIdx = _indexOfHeader(headerCells,
          ['id', 'student id', 'student_number', 'student no', 'student']);
      final nameIdx =
          _indexOfHeader(headerCells, ['name', 'full name', 'student name']);
      if (idIdx == -1 || nameIdx == -1) continue;

      for (var i = 1; i < trs.length; i++) {
        final cells = _cellsText(trs[i]);
        if (cells.isEmpty) continue;
        final id = (idIdx < cells.length ? cells[idIdx] : '').trim();
        final name = (nameIdx < cells.length ? cells[nameIdx] : '').trim();
        if (id.isEmpty || name.isEmpty) continue;
        rows.add({'id': id, 'name': name});
      }
      gotFromTables = rows.isNotEmpty;
      if (gotFromTables) break; // Take first matching table
    }
    if (gotFromTables) return rows;

    // Fallback: paragraphs (each line "ID Name")
    final paras =
        doc.findAllElements('p').map((p) => _texts(p).join('')).toList();
    for (final line in paras) {
      final s = line.trim();
      if (s.isEmpty) continue;

      // Heuristics: "123456 Keith Virgenes" or "ID: 123456 Name: Keith Virgenes"
      final m1 = RegExp(r'^([A-Za-z0-9\-]+)\s+(.+)$').firstMatch(s);
      final m2 = RegExp(r'ID\s*[:\-]\s*([A-Za-z0-9\-]+).*?Name\s*[:\-]\s*(.+)$',
              caseSensitive: false)
          .firstMatch(s);
      String id = '';
      String name = '';
      if (m2 != null) {
        id = m2.group(1)!.trim();
        name = m2.group(2)!.trim();
      } else if (m1 != null) {
        id = m1.group(1)!.trim();
        name = m1.group(2)!.trim();
      }
      if (id.isNotEmpty && name.isNotEmpty) {
        rows.add({'id': id, 'name': name});
      }
    }
    return rows;
  }

  static List<String> _cellsText(xml.XmlElement tr) {
    final cells = <String>[];
    for (final tc in tr.findAllElements('tc')) {
      final text = _texts(tc).join('');
      cells.add(text.trim());
    }
    return cells;
  }

  static List<String> _texts(xml.XmlElement el) =>
      el.findAllElements('t').map((e) => e.text).toList();

  static int _indexOfHeader(List<String> headers, List<String> candidates) {
    final norm = headers.map((h) => h.toLowerCase().trim()).toList();
    for (final c in candidates) {
      final idx = norm.indexOf(c);
      if (idx != -1) return idx;
    }

    // contains
    for (var i = 0; i < norm.length; i++) {
      if (candidates.any((c) => norm[i].contains(c))) return i;
    }
    return -1;
  }
}
