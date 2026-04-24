import 'dart:io';
import 'dart:typed_data';

import 'models/ocr_result.dart';
import 'ocr_method_channel.dart';
import 'ocr_platform_interface.dart';
import 'validators/ocr_validator.dart';

class OcrReader {
  final OcrPlatformInterface _platform;

  /// When true, rejects empty and handwritten images.
  bool validateDocument;

  /// When true, automatically masks Aadhaar numbers if detected.
  bool maskAadhaar;

  /// Custom validator thresholds.
  final OcrValidator validator;

  OcrReader({
    OcrPlatformInterface? platform,
    this.validateDocument = false,
    this.maskAadhaar = false,
    OcrValidator? validator,
  })  : _platform = platform ?? OcrMethodChannel(),
        validator = validator ?? const OcrValidator();

  Future<OcrResult> _process(Future<OcrResult> result) async {
    final r = await result;
    if (validateDocument) validator.validate(r);
    return maskAadhaar ? r.maskAadhaar() : r;
  }

  /// Recognize English text from an image file path.
  /// Non-English text (Tamil, Hindi, etc.) is automatically filtered out.
  Future<OcrResult> readFromPath(String imagePath) {
    if (!File(imagePath).existsSync()) {
      throw ArgumentError('File not found: $imagePath');
    }
    return _process(_platform.recognizeFromPath(imagePath));
  }

  /// Recognize English text from raw image bytes.
  Future<OcrResult> readFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) throw ArgumentError('Image bytes cannot be empty');
    return _process(_platform.recognizeFromBytes(bytes));
  }

  /// Recognize English text from a [File].
  Future<OcrResult> readFromFile(File file) => readFromPath(file.path);

  /// Release native resources.
  Future<void> dispose() => _platform.dispose();
}
