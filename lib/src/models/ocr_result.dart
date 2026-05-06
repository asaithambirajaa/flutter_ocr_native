import 'dart:typed_data';
import 'dart:ui';

import '../validators/document_number_validator.dart';
import '../validators/document_type_detector.dart';

class OcrResult {
  final String text;
  final List<TextBlock> blocks;

  /// Whether the native image analysis detected this as printed text.
  final bool isPrinted;

  /// Image bytes with Aadhaar number visually masked (black rectangles).
  /// Null if no Aadhaar number was detected in the image.
  final Uint8List? maskedImageBytes;

  /// Original unmasked text — used internally for validation.
  final String _rawText;

  /// The original unmasked text — use for validation and number extraction.
  String get rawText => _rawText;

  OcrResult({
    required this.text,
    required this.blocks,
    this.isPrinted = false,
    this.maskedImageBytes,
    String? rawText,
  }) : _rawText = rawText ?? text;

  factory OcrResult.fromMap(Map<String, dynamic> map) {
    final blocks = (map['blocks'] as List?)
            ?.map((b) => TextBlock.fromMap(Map<String, dynamic>.from(b)))
            .toList() ??
        [];
    final imageBytes = map['maskedImageBytes'];
    final text = map['text'] ?? '';
    return OcrResult(
      text: text,
      blocks: blocks,
      isPrinted: map['isPrinted'] ?? false,
      maskedImageBytes: imageBytes is Uint8List ? imageBytes : null,
      rawText: text,
    );
  }

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  /// Auto-detected document type based on OCR text content.
  DetectedDocType get docType => DocumentTypeDetector.detect(_rawText);

  /// Human-readable label for the detected document type.
  String get docTypeLabel => DocumentTypeDetector.label(docType);

  /// Whether an Aadhaar number was detected and the image was masked.
  bool get hasAadhaar => maskedImageBytes != null;

  /// Whether the detected Aadhaar number is valid (Verhoeff checksum).
  /// Validates against the original unmasked text.
  bool get isAadhaarValid => DocumentNumberValidator.extractAadhaar(_rawText) != null;

  /// Aadhaar validation error message. Null if valid or not found.
  String? get aadhaarError {
    // Try with separators
    final match = RegExp(r'(?<!\d)(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})(?!\d)').firstMatch(_rawText);
    if (match != null) {
      final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
      return DocumentNumberValidator.validateAadhaar(number);
    }
    // Try without separators
    final noSepMatch = RegExp(r'(?<!\d)(\d{12})(?!\d)').firstMatch(_rawText);
    if (noSepMatch != null) {
      return DocumentNumberValidator.validateAadhaar(noSepMatch.group(1)!);
    }
    return 'Aadhaar number not found';
  }

  /// Whether a valid PAN number is present in the text.
  bool get isPanValid => DocumentNumberValidator.extractPAN(_rawText) != null;

  /// PAN validation error message. Null if valid or not found.
  String? get panError {
    final match = RegExp(r'[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]').firstMatch(_rawText.toUpperCase());
    if (match == null) return 'PAN number not found';
    return DocumentNumberValidator.validatePAN(match.group(0)!);
  }

  /// The detected PAN holder type (Individual, Company, etc.) or null.
  String? get panHolderType {
    final pan = DocumentNumberValidator.extractPAN(_rawText);
    return pan != null ? DocumentNumberValidator.panHolderType(pan) : null;
  }

  /// Returns a new [OcrResult] with Aadhaar numbers masked in text.
  OcrResult maskAadhaar() => _maskAadhaar(this);
}

class TextBlock {
  final String text;
  final Rect boundingBox;
  final List<TextLine> lines;
  final String? recognizedLanguage;

  const TextBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
    this.recognizedLanguage,
  });

  factory TextBlock.fromMap(Map<String, dynamic> map) {
    final rect = _parseRect(map['boundingBox']);
    final lines = (map['lines'] as List?)
            ?.map((l) => TextLine.fromMap(Map<String, dynamic>.from(l)))
            .toList() ??
        [];
    return TextBlock(
      text: map['text'] ?? '',
      boundingBox: rect,
      lines: lines,
      recognizedLanguage: map['recognizedLanguage'],
    );
  }
}

class TextLine {
  final String text;
  final Rect boundingBox;
  final List<TextElement> elements;
  final double? confidence;

  const TextLine({
    required this.text,
    required this.boundingBox,
    required this.elements,
    this.confidence,
  });

  factory TextLine.fromMap(Map<String, dynamic> map) {
    final rect = _parseRect(map['boundingBox']);
    final elements = (map['elements'] as List?)
            ?.map((e) => TextElement.fromMap(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
    return TextLine(
      text: map['text'] ?? '',
      boundingBox: rect,
      elements: elements,
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }
}

class TextElement {
  final String text;
  final Rect boundingBox;
  final double? confidence;

  const TextElement({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  factory TextElement.fromMap(Map<String, dynamic> map) {
    final rect = _parseRect(map['boundingBox']);
    return TextElement(
      text: map['text'] ?? '',
      boundingBox: rect,
      confidence: (map['confidence'] as num?)?.toDouble(),
    );
  }
}

Rect _parseRect(dynamic map) {
  if (map == null) return Rect.zero;
  final m = Map<String, dynamic>.from(map);
  return Rect.fromLTWH(
    (m['left'] as num).toDouble(),
    (m['top'] as num).toDouble(),
    (m['width'] as num).toDouble(),
    (m['height'] as num).toDouble(),
  );
}

// Matches exactly 3 groups of 4 digits — not part of a longer number sequence
final _aadhaarPattern = RegExp(r'(?<!\d)(\d{4})([\s\-]+)(\d{4})([\s\-]+)(\d{4})(?!\d)');
// Matches 12 consecutive digits without separators
final _aadhaarPatternNoSep = RegExp(r'(?<!\d)(\d{12})(?!\d)');

String _maskAadhaarInText(String text) {
  // Mask with separators
  var masked = text.replaceAllMapped(_aadhaarPattern, (m) {
    return 'XXXX${m.group(2)}XXXX${m.group(4)}${m.group(5)}';
  });
  // Mask without separators (keep last 4 visible)
  if (masked == text) {
    masked = text.replaceAllMapped(_aadhaarPatternNoSep, (m) {
      final digits = m.group(1)!;
      return 'XXXXXXXX${digits.substring(8)}';
    });
  }
  return masked;
}

OcrResult _maskAadhaar(OcrResult result) {
  final match = _aadhaarPattern.firstMatch(result.text);
  final noSepMatch = match == null ? _aadhaarPatternNoSep.firstMatch(result.text) : null;
  final last4 = match?.group(5)
      ?? noSepMatch?.group(1)?.substring(8);

  return OcrResult(
    text: _maskAadhaarInText(result.text),
    isPrinted: result.isPrinted,
    maskedImageBytes: result.maskedImageBytes,
    rawText: result._rawText, // preserve original for validation
    blocks: result.blocks.map((block) {
      final maskedLines = block.lines.map((line) {
        final maskedLineText = _maskAadhaarInText(line.text);
        final lineWasMasked = maskedLineText != line.text;

        return TextLine(
          text: maskedLineText,
          boundingBox: line.boundingBox,
          confidence: line.confidence,
          elements: line.elements.map((el) {
            if (lineWasMasked &&
                last4 != null &&
                RegExp(r'^\d{4}$').hasMatch(el.text) &&
                el.text != last4) {
              return TextElement(
                text: 'XXXX',
                boundingBox: el.boundingBox,
                confidence: el.confidence,
              );
            }
            return el;
          }).toList(),
        );
      }).toList();

      return TextBlock(
        text: maskedLines.map((l) => l.text).join('\n'),
        boundingBox: block.boundingBox,
        recognizedLanguage: block.recognizedLanguage,
        lines: maskedLines,
      );
    }).toList(),
  );
}
