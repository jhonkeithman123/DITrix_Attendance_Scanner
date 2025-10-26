import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

class ScannerService {
  ScannerService({this.onLog});
  final void Function(String msg)? onLog;

  void _log(String m) {
    onLog?.call(m);
  }

  // Public API: run OCR regardless of platform
  Future<Map<String, dynamic>> runOcr(File imageFile) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _runMobileOcr(imageFile);
    }
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      _log('[OCR] Unsupported platform');
      return <String, dynamic>{};
    }
    return _runPythonOcr(imageFile);
  }

  // ---------------- Mobile (ML Kit) ----------------

  static const Set<String> _blacklist = {
    'university',
    'college',
    'philippines',
    'republic',
    'diploma',
    'bachelor',
    'technology',
    'camera',
    'report',
    'student',
    'department',
    'institute',
    'school',
    'polytechnic',
    'information'
  };

  Future<Map<String, dynamic>> _runMobileOcr(File imageFile) async {
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final input = InputImage.fromFilePath(imageFile.path);
      final result = await recognizer.processImage(input);
      await recognizer.close();

      final fullText = result.text;
      final student = _findStudentNumberFromMlkit(result) ??
          _findStudentNumberInText(fullText);
      final surname = _pickSurnameFromMlkit(result);

      _log(
          '[MLKit OCR] lines=${result.blocks.length} -> id="$student" name="$surname"');
      return {
        'student_number': student,
        'surname': surname,
        'analyzed': fullText
      };
    } catch (e) {
      _log('[MLKit OCR] failed: $e');
      return <String, dynamic>{};
    }
  }

  String? _findStudentNumberFromMlkit(RecognizedText rt) {
    int scoreLine(String text) {
      final t = text.toUpperCase();
      final digits = RegExp(r'\d').allMatches(t).length;
      final hasMn = t.contains('MN') || RegExp(r'M[NIHIVW]').hasMatch(t);
      return digits + (hasMn ? 6 : 0);
    }

    String? bestLine;
    int bestScore = -1;
    for (final b in rt.blocks) {
      for (final ln in b.lines) {
        final t = ln.text.trim();
        if (t.isEmpty) continue;
        final s = scoreLine(t);
        if (s > bestScore) {
          bestScore = s;
          bestLine = t;
        }
      }
    }
    if (bestLine == null) return null;
    String norm(String s) {
      s = s.toUpperCase().replaceAll('—', '-').replaceAll('–', '-');
      s = s.replaceAll(RegExp(r'[^A-Z0-9/\- ]'), ' ');
      s = s
          .replaceAll(RegExp(r'M[NIHIVW]'), '§MN§')
          .replaceAll('O', '0')
          .replaceAll('D', '0')
          .replaceAll('I', '1')
          .replaceAll('L', '1')
          .replaceAll('S', '5')
          .replaceAll('B', '8')
          .replaceAll('Z', '2')
          .replaceAll('G', '6')
          .replaceAll('§MN§', 'MN');
      return s.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final re =
        RegExp(r'(\d{4})[ \-\/]+(\d{4,6})[ \-\/]+M[NIHIVW][ \-\/]+(\d{1,2})');
    final masked = norm(bestLine);
    final m = re.firstMatch(masked);
    if (m != null) {
      return '${m.group(1)!}-${m.group(2)!}-MN-${m.group(3)!}';
    }
    for (final b in rt.blocks) {
      for (final ln in b.lines) {
        final mm = norm(ln.text);
        final m2 = re.firstMatch(mm);
        if (m2 != null) {
          return '${m2.group(1)!}-${m2.group(2)!}-MN-${m2.group(3)!}';
        }
      }
    }
    return null;
  }

  String _findStudentNumberInText(String text) {
    String t = text.toUpperCase().replaceAll('—', '-').replaceAll('–', '-');
    t = t
        .replaceAll(RegExp(r'[^A-Z0-9/\- ]'), ' ')
        .replaceAll(RegExp(r'M[NIHIVW]'), '§MN§')
        .replaceAll('O', '0')
        .replaceAll('D', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('S', '5')
        .replaceAll('B', '8')
        .replaceAll('Z', '2')
        .replaceAll('G', '6')
        .replaceAll('§MN§', 'MN')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final patterns = <RegExp>[
      RegExp(r'(\d{4})[ \-\/]+(\d{4,6})[ \-\/]+MN[ \-\/]+(\d{1,2})'),
      RegExp(r'(\d{3,})[ \-\/]+(\d{4,})[ \-\/]+MN[ \-\/]+(\d{1,2})'),
    ];
    for (final r in patterns) {
      final m = r.firstMatch(t);
      if (m != null) return '${m.group(1)!}-${m.group(2)!}-MN-${m.group(3)!}';
    }
    return '';
  }

  String _pickSurnameFromMlkit(RecognizedText rt) {
    final idLines = <double>[];
    for (final block in rt.blocks) {
      for (final line in block.lines) {
        final txt = (line.text).trim();
        if (txt.isEmpty) continue;
        if (RegExp(r'\d').hasMatch(txt) &&
            RegExp(r'MN', caseSensitive: false).hasMatch(txt)) {
          final y = line.boundingBox.center.dy;
          idLines.add(y);
        }
      }
    }
    final double bandY = idLines.isNotEmpty
        ? idLines.reduce((a, b) => a + b) / idLines.length
        : -1;
    const double tol = 160;

    String best = '';
    double bestHeight = -1;

    for (final block in rt.blocks) {
      for (final line in block.lines) {
        final ly = line.boundingBox.center.dy;
        final nearId = bandY > 0 ? ((ly - bandY).abs() <= tol) : true;
        for (final el in line.elements) {
          final w = (el.text).trim();
          if (w.isEmpty) continue;
          if (!RegExp(r'^[A-Za-z]+$').hasMatch(w)) continue;
          if (w.length < 3 || w.length > 14) continue;
          if (_blacklist.contains(w.toLowerCase())) continue;
          if (RegExp(r'philipp|philip|phillip', caseSensitive: false)
              .hasMatch(w)) continue;
          if (RegExp(r'(.)\1\1', caseSensitive: false).hasMatch(w)) continue;
          if (!nearId && bandY > 0) continue;
          final h = el.boundingBox.height;
          if (h > bestHeight) {
            bestHeight = h;
            best =
                w.substring(0, 1).toUpperCase() + w.substring(1).toLowerCase();
          }
        }
      }
    }

    if (best.isNotEmpty) return best;

    for (final w in rt.text.split(RegExp(r'\s+'))) {
      if (RegExp(r'^[A-Za-z]{3,}$').hasMatch(w) &&
          !_blacklist.contains(w.toLowerCase()) &&
          !RegExp(r'philipp|philip|phillip', caseSensitive: false)
              .hasMatch(w) &&
          !RegExp(r'(.)\1\1', caseSensitive: false).hasMatch(w)) {
        if (w.length > best.length) best = w;
      }
    }
    return best;
  }

  // ---------------- Desktop (Python) ----------------

  Future<Map<String, dynamic>> _runPythonOcr(File imageFile) async {
    try {
      final cwd = Directory.current.path;
      final candidates = <String>[
        p.join(cwd, 'lib', 'scanner_service', 'scan.py'),
        p.join(cwd, 'ocr', 'ocr_id.py'),
        p.normalize(p.join(cwd, '..', 'lib', 'scanner_service', 'scan.py')),
      ];
      final envOverride = Platform.environment['OCR_SCRIPT'];
      if (envOverride != null && envOverride.isNotEmpty) {
        candidates.insert(0, envOverride);
      }
      String? scriptPath;
      for (final c in candidates) {
        if (await File(c).exists()) {
          scriptPath = c;
          break;
        }
      }
      if (scriptPath == null) {
        _log(
            '[PY OCR] script not found. Use env OCR_SCRIPT to point to scan.py');
        return <String, dynamic>{};
      }

      _log('[PY OCR] using script: $scriptPath');

      final pythonFromEnv = Platform.environment['PYTHON_EXE'];
      final condaPrefix = Platform.environment['CONDA_PREFIX'];
      final condaPython = (condaPrefix != null && condaPrefix.isNotEmpty)
          ? p.join(condaPrefix, 'bin', 'python')
          : null;

      final exeCandidates = <String>[
        if (pythonFromEnv != null && pythonFromEnv.isNotEmpty) pythonFromEnv,
        if (condaPython != null) condaPython,
        'python3',
        'python',
      ];

      ProcessResult? res;
      for (final exe in exeCandidates) {
        try {
          _log('[PY OCR] running: $exe "$scriptPath" "${imageFile.path}"');
          res = await Process.run(
            exe,
            [scriptPath, imageFile.path],
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );
          if (res.exitCode == 0) break;
        } catch (e) {
          _log('[PY OCR] failed starting "$exe": $e');
        }
      }
      if (res == null) {
        _log('[PY OCR] no python interpreter found');
        return <String, dynamic>{};
      }

      final outStr = res.stdout is String
          ? (res.stdout as String)
          : utf8.decode(res.stdout);
      final errStr = res.stderr is String
          ? (res.stderr as String)
          : utf8.decode(res.stderr ?? []);
      _log('[PY OCR] exit=${res.exitCode}');
      if (errStr.isNotEmpty) {
        _log(
            '[PY OCR][stderr] ${errStr.length > 300 ? '${errStr.substring(0, 300)}...' : errStr}');
      }
      if (outStr.isEmpty) {
        _log('[PY OCR] empty stdout');
        return <String, dynamic>{};
      }

      Map<String, dynamic> parsed = {};
      final start = outStr.indexOf('{');
      final end = outStr.lastIndexOf('}');
      if (start != -1 && end != -1 && end >= start) {
        final slice = outStr.substring(start, end + 1);
        try {
          parsed = jsonDecode(slice) as Map<String, dynamic>;
          _log('[PY OCR] parsed JSON: ${jsonEncode(parsed)}');
        } catch (e) {
          _log('[PY OCR] json decode failed: $e');
        }
      } else {
        _log('[PY OCR] no JSON braces found in stdout');
      }
      return parsed;
    } catch (e) {
      _log('[PY OCR] failed: $e');
      return <String, dynamic>{};
    }
  }
}
