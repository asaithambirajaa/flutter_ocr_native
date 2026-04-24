import 'dart:typed_data';
import 'dart:ui';

class OcrResult {
  final String text;
  final List<TextBlock> blocks;

  /// Whether the native image analysis detected this as printed text.
  final bool isPrinted;

  /// Image bytes with Aadhaar number visually masked (black rectangles).
  /// Null if no Aadhaar number was detected in the image.
  final Uint8List? maskedImageBytes;

  const OcrResult({
    required this.text,
    required this.blocks,
    this.isPrinted = false,
    this.maskedImageBytes,
  });

  factory OcrResult.fromMap(Map<String, dynamic> map) {
    final blocks = (map['blocks'] as List?)
            ?.map((b) => TextBlock.fromMap(Map<String, dynamic>.from(b)))
            .toList() ??
        [];
    final imageBytes = map['maskedImageBytes'];
    return OcrResult(
      text: map['text'] ?? '',
      blocks: blocks,
      isPrinted: map['isPrinted'] ?? false,
      maskedImageBytes: imageBytes is Uint8List ? imageBytes : null,
    );
  }

  bool get isEmpty => text.isEmpty;
  bool get isNotEmpty => text.isNotEmpty;

  /// Whether an Aadhaar number was detected and the image was masked.
  bool get hasAadhaar => maskedImageBytes != null;

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

final _aadhaarPattern = RegExp(r'(\d{4})([\s\-]*)(\d{4})([\s\-]*)(\d{4})');

String _maskAadhaarInText(String text) {
  return text.replaceAllMapped(_aadhaarPattern, (m) {
    return 'XXXX${m.group(2)}XXXX${m.group(4)}${m.group(5)}';
  });
}

OcrResult _maskAadhaar(OcrResult result) {
  final match = _aadhaarPattern.firstMatch(result.text);
  final last4 = match?.group(5);

  return OcrResult(
    text: _maskAadhaarInText(result.text),
    isPrinted: result.isPrinted,
    maskedImageBytes: result.maskedImageBytes,
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
