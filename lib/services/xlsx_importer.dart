import 'dart:io';
import 'package:excel/excel.dart';

/// Simple XLSX/XLS parser returning a map of sheetName -> rows.
/// Each row is represented as Map<String, dynamic> where keys come from the header row.
class XlsxImporter {
  /// Parse [file] and return Map<sheetName, List<rowMaps>>
  /// First non-empty row is treated as header. Empty rows are skipped.
  static Map<String, List<Map<String, dynamic>>> parse(File file) {
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final result = <String, List<Map<String, dynamic>>>{};

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName];
      if (sheet == null) continue;
      final rows = sheet.rows;
      if (rows.isEmpty) {
        result[sheetName] = [];
        continue;
      }

      // header row -> column keys
      final headerRow = rows.first;
      final headers = List<String>.generate(
        headerRow.length,
        (i) => headerRow[i]?.value?.toString() ?? 'col_$i',
      );

      final parsedRows = <Map<String, dynamic>>[];
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        // skip empty rows
        if (row.every((c) =>
            c == null ||
            c.value == null ||
            c.value.toString().trim().isEmpty)) {
          continue;
        }
        final map = <String, dynamic>{};
        for (var c = 0; c < headers.length; c++) {
          final cell = (c < row.length) ? row[c] : null;
          map[headers[c]] = cell?.value;
        }
        parsedRows.add(map);
      }

      result[sheetName] = parsedRows;
    }

    return result;
  }
}
