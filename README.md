# flutter_ocr_native

A Flutter plugin for extracting text from images using native on-device OCR engines — **no third-party Dart OCR packages required**.

- **Android**: Google ML Kit Text Recognition
- **iOS**: Apple Vision Framework

## Features

- Read text from image file path, `File`, or raw bytes
- Structured results: blocks → lines → elements with bounding boxes & confidence scores
- English-only extraction — non-Latin scripts auto-filtered
- Aadhaar number masking (text + image) — configurable
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
  flutter_ocr_native: ^0.0.7
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

### iOS

Minimum iOS 13.0. Set in `ios/Podfile`:

```ruby
platform :ios, '13.0'
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

### Document Viewer

```dart
// One-liner full-screen viewer with pinch-to-zoom
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

// Or use as a widget
OcrDocumentViewer(
  result: result,
  originalFile: imageFile,
  watermark: watermark,
  minScale: 0.5,
  maxScale: 5.0,
)
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
  // Optional styling:
  // textColor: Color(0xCCFFFFFF),
  // backgroundColor: Color(0xB3000000),
  // fontSize: 12,
);

// Auto downloads to platform-specific folder
// Android: /storage/emulated/0/Download/
// iOS: App Documents (visible in Files app)
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
  watermark: watermark,
);

// Or from bytes
final file = await OcrDocumentSaver.download(
  result: result,
  originalImageBytes: imageBytes,
  watermark: watermark,
);

// Save to custom directory
final file = await OcrDocumentSaver.save(
  result: result,
  originalImageBytes: imageBytes,
  directory: myDirectory,
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

// Auto-detect format from file extension
// .png → PNG, .jpg/.webp/etc → JPEG
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: 'photo.png',      // saves as PNG
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
    │   ├── ocr_exception.dart             # EmptyImageException, HandwrittenTextException
    │   ├── ocr_result.dart                # OcrResult, TextBlock, TextLine, TextElement
    │   └── ocr_watermark.dart             # OcrWatermark config
    ├── utils/
    │   └── ocr_document_saver.dart        # Download & save with watermark
    ├── validators/
    │   └── ocr_validator.dart             # Document validation
    ├── widgets/
    │   └── ocr_document_viewer.dart       # Full-screen viewer widget
    ├── ocr_platform_interface.dart         # Abstract platform contract
    ├── ocr_method_channel.dart             # MethodChannel implementation
    └── ocr_reader.dart                    # Public API class

android/src/main/kotlin/com/flutter_ocr_native/
    └── OcrPlugin.kt                       # ML Kit OCR + Aadhaar masking + watermark

ios/Classes/
    └── OcrPlugin.swift                    # Vision OCR + Aadhaar masking + watermark
```

## Supported Platforms

| Platform | Min Version | OCR Engine |
|----------|-------------|------------|
| Android  | SDK 21      | Google ML Kit Text Recognition |
| iOS      | 13.0        | Apple Vision Framework |

## Flutter Compatibility

Requires Flutter 3.19.0+ (Dart SDK >=3.2.4 <4.0.0)
