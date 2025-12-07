import 'dart:io';
import 'package:flutter_pdf_text/flutter_pdf_text.dart';

//* This is a utility service that helps import a pdf files
class PdfImporter {
  static Future<List<Map<String, String>>> parseMasterlist(File file) async {
    final doc = await PDFDoc.fromFile(file);
    final pages = await doc.length;
    final out = <Map<String, String>>[];

    // Your IDs look like: 2025-11576-MN-0 (digits-dash-digits-dash-letters-dash-digit)
    final idRe = RegExp(r'\b\d{4}-\d{4,6}-[A-Za-z]{2}-\d\b');

    // Name tokens: uppercase words with commas, may include spaces and hyphens
    // Capture until end of line OR before next ID
    RegExp nameReAfter() {
      // Accept any letters and common punctuation, stop before double spaces + next ID handled below.
      return RegExp(r"\s+([A-Za-z ,\-\'\.]+)", multiLine: true);
    }

    String clean(String s) => s
        .replaceAll('\u00A0', ' ')
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();

    for (int i = 1; i <= pages; i++) {
      String txt;
      try {
        final page = await doc.pageAt(i);
        txt = await page.text;
      } catch (_) {
        continue;
      }
      if (txt.trim().isEmpty) continue;

      // Work on the whole page text, not split lines
      var cursor = 0;
      while (true) {
        final idMatch = idRe.matchAsPrefix(txt, cursor) ??
            idRe.firstMatch(txt.substring(cursor));
        if (idMatch == null) break;

        final id = idMatch.group(0)!;
        final afterIdx = cursor + idMatch.end - (idMatch.start == 0 ? 0 : 0);

        // Find name immediately after ID
        final nameMatch = nameReAfter().firstMatch(txt.substring(afterIdx));
        if (nameMatch != null) {
          var name = nameMatch.group(1) ?? '';
          // Stop name at the next ID if we accidentally spanned too far
          final nextId = idRe.firstMatch(name);
          if (nextId != null) {
            name = name.substring(0, nextId.start).trimRight();
          }
          name = clean(name);
          // Avoid header lines that contain "Student Number" etc.
          final lower = name.toLowerCase();
          if (name.isNotEmpty &&
              !(lower.contains('student') && lower.contains('number'))) {
            out.add({'id': id, 'name': name});
          }
        }

        cursor = cursor + idMatch.end; // advance cursor after ID
      }
    }

    // Deduplicate and finalize
    String normId(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final seen = <String>{};
    final result = <Map<String, String>>[];
    for (final r in out) {
      final id = (r['id'] ?? '').trim();
      var name = (r['name'] ?? '').trim();
      if (id.isEmpty || name.isEmpty) continue;

      // Normalize name like "LAST, FIRST MIDDLE" -> keep as-is
      // If name spans multiple lines in extraction, compress spaces
      name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

      final key = normId(id);
      if (!seen.contains(key)) {
        seen.add(key);
        result.add({'id': id, 'name': name});
      }
    }
    return result;
  }
}
