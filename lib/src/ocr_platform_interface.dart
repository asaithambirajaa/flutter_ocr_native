import 'dart:typed_data';

import 'models/ocr_result.dart';

abstract class OcrPlatformInterface {
  Future<OcrResult> recognizeFromPath(String imagePath);
  Future<OcrResult> recognizeFromBytes(Uint8List bytes);
  Future<Uint8List?> renderPdfPage(Uint8List pdfBytes, {int page = 0, double scale = 2.0});
  Future<int> getPdfPageCount(Uint8List pdfBytes);
  Future<void> dispose();
}
