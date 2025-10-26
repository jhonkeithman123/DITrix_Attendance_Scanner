import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;

Future<String> ocrExtractText(File imageFile) async {
  final bytes = await imageFile.readAsBytes();
  final image = img.decodeImage(bytes);

  if (image != null) {
    final maxW = 1400;
    final processed =
        image.width > maxW ? img.copyResize(image, width: maxW) : image;
    final cleanBytes = img.encodeJpg(processed, quality: 85);
    await imageFile.writeAsBytes(cleanBytes, flush: true);
  }

  final text =
      await FlutterTesseractOcr.extractText(imageFile.path, language: 'eng');
  return text;
}

Map<String, String> parseIdAndSurname(String text) {
  final cleaned = text.replaceAll('\n', ' ');
  final numberRe =
      RegExp(r'\b\d{4}-\d{3,6}-[A-Z]{1,3}-\d\b', caseSensitive: false);
  final numMatch = numberRe.firstMatch(cleaned);
  final studentNumber = numMatch?.group(0)?.replaceAll(' ', '') ?? '';

  String surname = '';
  final tokens = cleaned.split(RegExp(r'\s+'));

  for (var t in tokens) {
    final token = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (token.length >= 3 && token.toUpperCase() == token) {
      if (token.length > surname.length) surname = token;
    }
  }

  if (surname.isEmpty) {
    surname = tokens
        .map((t) => t.replaceAll(RegExp(r'[^A-Za-z]'), ''))
        .fold('', (p, n) => n.length > p.length ? n : p);
  }

  return {'student_number': studentNumber, 'surname': surname};
}
