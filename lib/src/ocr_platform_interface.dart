import 'dart:typed_data';

import 'models/ocr_result.dart';

abstract class OcrPlatformInterface {
  Future<OcrResult> recognizeFromPath(String imagePath);
  Future<OcrResult> recognizeFromBytes(Uint8List bytes);
  Future<void> dispose();
}
