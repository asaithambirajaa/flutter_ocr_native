import '../models/ocr_exception.dart';
import '../models/ocr_result.dart';
import '../validators/document_type_detector.dart';

/// Controls how handwriting detection behaves for a document type.
enum HandwritingPolicy {
  /// Reject if native analysis says not fully printed.
  /// Use for: Aadhaar, PAN, Voter ID — should always be fully printed.
  rejectIfHandwritten,

  /// Allow mixed handwriting — reject only if the document appears to be
  /// ENTIRELY handwritten (no printed keywords detected at all).
  /// Use for: Passport (has signature), Cheque (has handwritten amount/payee),
  /// Driving License (may have handwritten entries on old format).
  allowMixed,

  /// Skip handwriting check entirely for this document type.
  skip,
}

class OcrValidator {
  /// Minimum text length to consider the image has meaningful content.
  final int minTextLength;

  const OcrValidator({this.minTextLength = 10});

  /// Returns the handwriting policy for a given document type.
  /// Internal — used by [validate] automatically.
  static HandwritingPolicy _policyFor(DetectedDocType type) {
    switch (type) {
      case DetectedDocType.passport:
      case DetectedDocType.cheque:
      case DetectedDocType.drivingLicense:
        return HandwritingPolicy.allowMixed;
      case DetectedDocType.aadhaar:
      case DetectedDocType.pan:
      case DetectedDocType.voterId:
      case DetectedDocType.unknown:
        return HandwritingPolicy.rejectIfHandwritten;
    }
  }

  /// Validates the OCR result.
  ///
  /// [docType] — if provided, applies the correct handwriting policy for that
  /// document type. If null, auto-detects from OCR text.
  ///
  /// Throws [EmptyImageException] if no meaningful text found.
  /// Throws [HandwrittenTextException] if handwriting check fails.
  void validate(OcrResult result, {DetectedDocType? docType}) {
    // Empty check — always applies
    if (result.isEmpty ||
        result.blocks.isEmpty ||
        result.text.trim().length < minTextLength) {
      throw const EmptyImageException();
    }

    // Determine which document type we're dealing with
    final type = docType ?? DocumentTypeDetector.detect(result.text);
    final policy = _policyFor(type);

    switch (policy) {
      case HandwritingPolicy.rejectIfHandwritten:
        // Strict: native must say it's printed
        if (!result.isPrinted) {
          throw const HandwrittenTextException();
        }

      case HandwritingPolicy.allowMixed:
        // Lenient: only reject if it looks ENTIRELY handwritten —
        // i.e. native says not printed AND no printed keywords found at all.
        if (!result.isPrinted && _isEntirelyHandwritten(result.text, type)) {
          throw const HandwrittenTextException();
        }

      case HandwritingPolicy.skip:
        break;
    }
  }

  /// Returns true only when the text has NO printed document keywords at all,
  /// meaning the whole document was handwritten (not just a field).
  static bool _isEntirelyHandwritten(String text, DetectedDocType type) {
    final upper = text.toUpperCase();

    switch (type) {
      case DetectedDocType.passport:
        // A real passport always has at least one of these printed
        return !upper.contains('PASSPORT') &&
            !upper.contains('REPUBLIC') &&
            !upper.contains('NATIONALITY') &&
            !upper.contains('SURNAME') &&
            !upper.contains('GIVEN') &&
            !RegExp(r'P<[A-Z]{3}').hasMatch(upper) &&
            !RegExp(r'\b[A-Z]\d{7}\b').hasMatch(upper);

      case DetectedDocType.cheque:
        // A real cheque always has bank name, IFSC, or account number printed
        return !upper.contains('BANK') &&
            !upper.contains('IFSC') &&
            !upper.contains('MICR') &&
            !upper.contains('CTS') &&
            !RegExp(r'[A-Z]{4}0[A-Z0-9]{6}').hasMatch(upper) &&
            !RegExp(r'\d{9,18}').hasMatch(text);

      case DetectedDocType.drivingLicense:
        // A real DL always has licence/transport/RTO printed
        return !upper.contains('DRIVING') &&
            !upper.contains('LICENCE') &&
            !upper.contains('LICENSE') &&
            !upper.contains('TRANSPORT') &&
            !upper.contains('RTO') &&
            !RegExp(r'[A-Z]{2}\d{13,14}').hasMatch(upper);

      default:
        return true;
    }
  }
}
