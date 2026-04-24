# flutter_ocr_native

A Flutter plugin for extracting text from images using native on-device OCR engines — **no third-party Dart packages required**.

- **Android**: Google ML Kit Text Recognition
- **iOS**: Apple Vision Framework

## Features

- Read text from image file path, `File`, or raw bytes
- Structured results: blocks → lines → elements with bounding boxes & confidence scores
- English-only extraction — non-Latin scripts auto-filtered
- Aadhaar number masking (text + image)
- Handwriting detection — rejects non-printed documents
- Fully on-device — no network calls, works offline

## Getting Started

```yaml
dependencies:
  flutter_ocr_native: ^0.0.1
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

```dart
import 'package:flutter_ocr_native/flutter_ocr_native.dart';

final reader = OcrReader(
  validateDocument: true,  // reject empty & handwritten
  maskAadhaar: true,       // mask Aadhaar in text
);

try {
  final result = await reader.readFromPath('/path/to/image.jpg');

  // Masked text
  print(result.text); // "XXXX XXXX 2356"

  // Masked image (Aadhaar blacked out)
  if (result.hasAadhaar) {
    Image.memory(result.maskedImageBytes!);
  }

  // Structured data
  for (final block in result.blocks) {
    for (final line in block.lines) {
      print('${line.text} (confidence: ${line.confidence})');
    }
  }
} on EmptyImageException {
  print('No text found');
} on HandwrittenTextException {
  print('Handwritten — not accepted');
}

await reader.dispose();
```

## Architecture

```
lib/
├── flutter_ocr_native.dart               # Public barrel export
└── src/
    ├── models/
    │   ├── ocr_exception.dart             # Exception types
    │   └── ocr_result.dart                # OcrResult, TextBlock, TextLine, TextElement
    ├── validators/
    │   └── ocr_validator.dart             # Document validation
    ├── ocr_platform_interface.dart         # Abstract platform contract
    ├── ocr_method_channel.dart             # MethodChannel implementation
    └── ocr_reader.dart                    # Public API class
```
