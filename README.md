# flutter_ocr_native

A Flutter plugin for extracting text from images using native on-device OCR engines — **no third-party Dart OCR packages required**.

- **Android**: Google ML Kit Text Recognition
- **iOS**: Apple Vision Framework
- **macOS**: Apple Vision Framework
- **Windows**: Windows.Media.Ocr (WinRT)
- **Linux**: Tesseract OCR

## Features

- Read text from image file path, `File`, or raw bytes
- Structured results: blocks → lines → elements with bounding boxes & confidence scores
- English-only extraction — non-Latin scripts auto-filtered
- Aadhaar number masking (text + image) — configurable
- Aadhaar & PAN number validation (Verhoeff checksum, format check)
- Handwriting detection — rejects non-printed documents
- Document viewer with pinch-to-zoom
- Download with configurable watermark (Lead ID, Lat, Long, etc.)
- Watermark auto-scales to image resolution — always readable
- Configurable image compression (JPEG quality 1-100 or PNG lossless)
- Supports any input image format (JPEG, PNG, WEBP, BMP, GIF, HEIC, TIFF)
- Platform-specific download paths handled internally
- Fully on-device — no network calls, works offline

## Getting Started

```yaml
dependencies:
  flutter_ocr_native: ^0.1.0
```

### Android

Minimum SDK 21. Add to `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdk 21
    }
}
```

### iOS / macOS

iOS minimum 13.0, macOS minimum 10.15.

### Windows

Requires Windows 10+. No additional setup.

### Linux

Requires Tesseract:
```bash
sudo apt install libtesseract-dev tesseract-ocr-eng libleptonica-dev
```

## Usage

### Basic OCR

```dart
import 'package:flutter_ocr_native/flutter_ocr_native.dart';

final reader = OcrReader();
final result = await reader.readFromPath('/path/to/image.jpg');
print(result.text);

// From File
final result = await reader.readFromFile(File('image.png'));

// From bytes
final result = await reader.readFromBytes(imageBytes);

// Structured data
for (final block in result.blocks) {
  for (final line in block.lines) {
    print('${line.text} (confidence: ${line.confidence})');
  }
}

await reader.dispose();
```

### Validation & Aadhaar Masking

```dart
final reader = OcrReader(
  validateDocument: true,  // reject empty & handwritten
  maskAadhaar: true,       // mask Aadhaar in text
);

try {
  final result = await reader.readFromPath('/path/to/aadhaar.jpg');

  // Masked text
  print(result.text); // "XXXX XXXX 2356"

  // Masked image (Aadhaar digits blacked out)
  if (result.hasAadhaar) {
    Image.memory(result.maskedImageBytes!);
  }
} on EmptyImageException {
  print('No text found');
} on HandwrittenTextException {
  print('Handwritten — not accepted');
}
```

### Document Number Validation

```dart
final result = await reader.readFromPath(path);

// Aadhaar validation
if (result.isAadhaarValid) {
  print('Valid Aadhaar');
} else {
  print(result.aadhaarError); // "Aadhaar checksum invalid"
}

// PAN validation
if (result.isPanValid) {
  print('Valid PAN — ${result.panHolderType}'); // "Individual"
} else {
  print(result.panError); // "PAN 4th character is invalid holder type"
}

// Standalone validation
DocumentNumberValidator.isValidAadhaar('5399 8956 2356'); // true/false
DocumentNumberValidator.validateAadhaar('0000 0000 0000'); // "Aadhaar cannot start with 0"
DocumentNumberValidator.isValidPAN('ABCPD1234F'); // true/false
DocumentNumberValidator.validatePAN('ABCXD1234F'); // "PAN 4th character is invalid holder type"
```

### Document Details Parsing

```dart
final details = AadhaarDetails.fromText(result.text);
print(details.name);          // "Ram Deva"
print(details.fatherName);    // "Shiv Kumar"
print(details.dob);           // "01/08/1994"
print(details.gender);        // "Male"
print(details.address);       // "123 Main St, Chennai 600001"
print(details.aadhaarNumber); // "5399 8956 2356"

// Or use the ready-made widget
OcrDetailsCard(result: result, maskAadhaar: true)
```

### Document Viewer

```dart
OcrDocumentViewer.show(
  context,
  result: result,
  originalFile: imageFile,
  title: 'My Document',
  watermark: OcrWatermark(lines: {
    'Lead ID': 'LD-20250101-001',
    'Lat': '12.9716',
    'Long': '77.5946',
  }),
  onSave: (bytes) async {
    await OcrDocumentSaver.downloadBytes(imageBytes: bytes);
  },
);
```

### Download with Watermark

```dart
final watermark = OcrWatermark(
  lines: {
    'Lead ID': 'LD-20250101-001',
    'Lat': '12.9716',
    'Long': '77.5946',
    'Agent': 'Ram Kumar',
    'Date': '2025-01-15 10:30',
  },
);

// Auto downloads to platform-specific folder
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
  watermark: watermark,
);

// Download without watermark — just omit it
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
);
```

### Image Compression

```dart
// JPEG with quality (default 90)
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
  imageQuality: 70,                    // JPEG 70%
);

// PNG lossless
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
  format: OcrImageFormat.png,
);

// Standalone compress any image
final compressed = await OcrDocumentSaver.compressImage(
  anyImageBytes,
  quality: 60,
);
```

### Custom Validator

```dart
final reader = OcrReader(
  validateDocument: true,
  validator: OcrValidator(minTextLength: 20),
);
```

### Toggle at Runtime

```dart
reader.validateDocument = false;
reader.maskAadhaar = false;
```

## Architecture

```
lib/
├── flutter_ocr_native.dart               # Public barrel export
└── src/
    ├── models/
    │   ├── aadhaar_details.dart            # AadhaarDetails parser
    │   ├── ocr_exception.dart             # EmptyImageException, HandwrittenTextException
    │   ├── ocr_result.dart                # OcrResult, TextBlock, TextLine, TextElement
    │   └── ocr_watermark.dart             # OcrWatermark config
    ├── utils/
    │   └── ocr_document_saver.dart        # Download & save with watermark
    ├── validators/
    │   ├── document_number_validator.dart  # Aadhaar & PAN validation
    │   └── ocr_validator.dart             # Document validation
    ├── widgets/
    │   ├── ocr_details_card.dart          # Structured details card widget
    │   └── ocr_document_viewer.dart       # Full-screen viewer widget
    ├── ocr_platform_interface.dart         # Abstract platform contract
    ├── ocr_method_channel.dart             # MethodChannel implementation
    └── ocr_reader.dart                    # Public API class

android/src/main/kotlin/com/flutter_ocr_native/
    └── OcrPlugin.kt                       # ML Kit OCR + Aadhaar masking + watermark

ios/Classes/
    └── OcrPlugin.swift                    # Vision OCR + Aadhaar masking + watermark

macos/Classes/
    └── OcrPlugin.swift                    # Vision OCR (macOS)

windows/
    └── ocr_plugin.cpp                     # WinRT OCR + GDI+

linux/
    └── ocr_plugin.cc                      # Tesseract OCR + Leptonica
```

## Supported Platforms

| Platform | Min Version | OCR Engine |
|----------|-------------|------------|
| Android  | SDK 21      | Google ML Kit Text Recognition |
| iOS      | 13.0        | Apple Vision Framework |
| macOS    | 10.15       | Apple Vision Framework |
| Windows  | 10          | Windows.Media.Ocr (WinRT) |
| Linux    | Any         | Tesseract OCR |

## Flutter Compatibility

Requires Flutter 3.19.0+ (Dart SDK >=3.2.4 <4.0.0)
