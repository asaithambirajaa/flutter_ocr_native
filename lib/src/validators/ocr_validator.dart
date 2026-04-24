import '../models/ocr_exception.dart';
import '../models/ocr_result.dart';

class OcrValidator {
  /// Minimum text length to consider the image has meaningful content.
  final int minTextLength;

  const OcrValidator({this.minTextLength = 10});

  /// Validates the OCR result.
  /// Throws [EmptyImageException] if no meaningful text found.
  /// Throws [HandwrittenTextException] if native analysis detected handwriting.
  void validate(OcrResult result) {
    if (result.isEmpty ||
        result.blocks.isEmpty ||
        result.text.trim().length < minTextLength) {
      throw const EmptyImageException();
    }

    if (!result.isPrinted) {
      throw const HandwrittenTextException();
    }
  }
}
