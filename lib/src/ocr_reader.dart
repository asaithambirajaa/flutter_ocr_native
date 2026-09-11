import 'dart:io';
import 'dart:typed_data';

import 'models/ocr_result.dart';
import 'ocr_method_channel.dart';
import 'ocr_platform_interface.dart';
import 'security/ocr_integrity.dart';
import 'utils/ocr_document_saver.dart';
import 'validators/document_type_detector.dart';
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
    this.validateDocument = false,
    this.maskAadhaar = false,
    OcrValidator? validator,
  })  : _platform = OcrMethodChannel(),
        validator = validator ?? const OcrValidator();

  /// Runs OCR on [bytes]. If the result is empty or low-confidence,
  /// automatically enhances the image (grayscale + Otsu binarization +
  /// unsharp mask) and retries once — transparent to the caller.
  Future<OcrResult> _processWithFallback(
    Uint8List bytes, {
    DetectedDocType? docType,
  }) async {
    final first = await _platform.recognizeFromBytes(bytes);

    final confidences = first.blocks
        .expand((b) => b.lines)
        .map((l) => l.confidence ?? 0.0)
        .toList();
    final avg = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;

    // Always enhance + retry when first pass is low-confidence or empty.
    // Validation only runs AFTER we have the best possible result — never on
    // the raw first pass — so a faded/laminated document gets a fair chance.
    OcrResult best;
    if (first.text.trim().isEmpty || avg < OcrIntegrity.minConfidence) {
      final enhanced = await OcrDocumentSaver.enhanceForOcr(bytes);
      final second = await _platform.recognizeFromBytes(enhanced);
      best = second.text.length >= first.text.length ? second : first;
    } else {
      best = first;
    }

    if (validateDocument) validator.validate(best, docType: docType);
    return maskAadhaar ? best.maskAadhaar() : best;
  }

  /// Recognize English text from an image file path.
  /// Automatically enhances and retries if the first OCR pass is low-quality.
  /// [docType] — hint the document type to apply correct handwriting policy.
  Future<OcrResult> readFromPath(String imagePath, {DetectedDocType? docType}) async {
    if (!await File(imagePath).exists()) {
      throw ArgumentError('File not found: $imagePath');
    }
    final bytes = await File(imagePath).readAsBytes();
    return _processWithFallback(bytes, docType: docType);
  }

  /// Recognize English text from raw image bytes.
  /// Automatically enhances and retries if the first OCR pass is low-quality.
  /// [docType] — hint the document type to apply correct handwriting policy.
  Future<OcrResult> readFromBytes(Uint8List bytes, {DetectedDocType? docType}) {
    if (bytes.isEmpty) throw ArgumentError('Image bytes cannot be empty');
    return _processWithFallback(bytes, docType: docType);
  }

  /// Recognize English text from a [File].
  /// [docType] — hint the document type to apply correct handwriting policy.
  Future<OcrResult> readFromFile(File file, {DetectedDocType? docType}) =>
      readFromPath(file.path, docType: docType);

  /// Recognize text from a PDF file (renders page to image first).
  /// [page] — zero-based page index (default 0).
  /// [scale] — render quality (default 2.0, higher = better OCR but slower).
  /// [docType] — hint the document type to apply correct handwriting policy.
  /// Uses native PDF rendering — no third-party packages needed.
  Future<OcrResult> readFromPdf(Uint8List pdfBytes,
      {int page = 0, double scale = 2.0, DetectedDocType? docType}) async {
    final imageBytes = await OcrDocumentSaver.renderPdfPage(pdfBytes, page: page, scale: scale);
    if (imageBytes == null) {
      throw ArgumentError('Failed to render PDF page $page. Platform may not support PDF rendering.');
    }
    return readFromBytes(imageBytes, docType: docType);
  }

  /// Recognize text from a PDF file path.
  /// [docType] — hint the document type to apply correct handwriting policy.
  Future<OcrResult> readFromPdfFile(File pdfFile,
      {int page = 0, double scale = 2.0, DetectedDocType? docType}) async {
    final bytes = await pdfFile.readAsBytes();
    return readFromPdf(bytes, page: page, scale: scale, docType: docType);
  }

  /// Release native resources.
  Future<void> dispose() => _platform.dispose();
}
