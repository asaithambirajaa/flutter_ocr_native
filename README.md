# flutter_ocr_native

A Flutter plugin for extracting text from images **and PDFs** using native on-device OCR engines — **no third-party Dart OCR packages required**.

- **Android**: Google ML Kit Text Recognition
- **iOS**: Apple Vision Framework
- **macOS**: Apple Vision Framework
- **Windows**: Windows.Media.Ocr (WinRT)
- **Linux**: Tesseract OCR

## Features

- Read text from image file path, `File`, or raw bytes
- **Native PDF to image** — render PDF pages without third-party packages
- Structured results: blocks → lines → elements with bounding boxes & confidence scores
- English-only extraction — non-Latin scripts auto-filtered
- **Auto-orientation correction** — detects correct image rotation using OCR confidence
- **Image cropper** with rotate support — crop & rotate before OCR
- **Capture instructions widget** — show best practices before scan/upload
- **Document type auto-detection** — Aadhaar, PAN, Passport, Driving License, Voter ID, Cheque
- **Document details parsing** — structured fields from OCR text (name, DOB, address, etc.)
- **Unified `DocumentDetails` model** — single API for all document types
- Aadhaar number masking (text + image) — configurable
- Aadhaar & PAN number validation (Verhoeff checksum, format check)
- Passport, Driving License, Voter ID, IFSC, Account number validation
- **Face extraction** from document images (Android, iOS, macOS)
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
  flutter_ocr_native: ^0.3.0
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
log(result.text);

// From File
final result = await reader.readFromFile(File('image.png'));

// From bytes
final result = await reader.readFromBytes(imageBytes);

// From PDF (native rendering — no third-party packages)
final result = await reader.readFromPdf(pdfBytes, page: 0);
final result = await reader.readFromPdfFile(File('document.pdf'));

// Structured data
for (final block in result.blocks) {
  for (final line in block.lines) {
    log('${line.text} (confidence: ${line.confidence})');
  }
}

await reader.dispose();
```

### PDF to Image (Native)

Render PDF pages to images natively — no Dart PDF packages needed.

```dart
// Render single page
final imageBytes = await OcrDocumentSaver.renderPdfPage(
  pdfBytes,
  page: 0,      // zero-based index
  scale: 2.0,   // render quality (2x = good for OCR)
);

// Get page count
final count = await OcrDocumentSaver.getPdfPageCount(pdfBytes);

// Render all pages
final allPages = await OcrDocumentSaver.renderAllPdfPages(pdfBytes);

// Direct PDF → OCR (single call)
final result = await reader.readFromPdf(pdfBytes);
```

| Platform | PDF Engine |
|----------|------------|
| Android  | `PdfRenderer` (API 21+) |
| iOS      | `CGPDFDocument` |
| macOS    | `CGPDFDocument` |
| Windows  | `Windows.Data.Pdf` |
| Linux    | Not supported (returns null) |

### Auto-Orientation Correction

Automatically detects and corrects image rotation — works even without EXIF data.
Uses OCR confidence scoring across all 4 rotations to find the readable orientation.

```dart
// Correct orientation before processing
final corrected = await OcrDocumentSaver.correctOrientation(imageBytes);

// Image is now upright — use for cropping, viewing, or OCR
final result = await reader.readFromBytes(corrected);
```

### Image Cropper with Rotate

```dart
// Show crop UI — includes rotate button (90° clockwise)
final cropped = await OcrImageCropper.show(
  context,
  imageBytes: correctedBytes,
  title: 'Crop Document',
);

if (cropped != null) {
  final result = await reader.readFromBytes(cropped);
}
```

### Capture Instructions (Show Before Scan)

Guide users on best angle, lighting, and document clarity before capture.

```dart
// Bottom sheet (recommended for mobile)
final proceed = await OcrCaptureInstructions.showAsBottomSheet(context);
if (proceed != true) return;
// Now open camera/gallery...

// Dialog
await OcrCaptureInstructions.showAsDialog(context);

// Custom instructions
OcrCaptureInstructions.showAsBottomSheet(
  context,
  title: 'PAN Card Upload Tips',
  customInstructions: [
    OcrInstruction(
      icon: Icons.credit_card,
      title: 'Front Side Only',
      description: 'Upload only the front side of your PAN card.',
      color: Colors.indigo,
    ),
  ],
);

// Inline widget
OcrCaptureInstructions() // embed directly in your UI
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
  log(result.text); // "XXXX XXXX 2356"

  // Masked image (Aadhaar digits blacked out)
  if (result.hasAadhaar) {
    Image.memory(result.maskedImageBytes!);
  }
} on EmptyImageException {
  log('No text found');
} on HandwrittenTextException {
  log('Handwritten — not accepted');
}
```

### Document Type Auto-Detection

```dart
final result = await reader.readFromBytes(imageBytes);

// Auto-detect document type
log(result.docType);      // DetectedDocType.aadhaar
log(result.docTypeLabel); // "Aadhaar"
```

### Unified Document Details

```dart
// Single API for all document types — parses fields + extracts face
final details = await DocumentDetails.fromResult(
  result,
  imageBytes: processedBytes,
);

log(details.docType);         // DetectedDocType.aadhaar
log(details.documentNumber);  // "5399 8956 2356"
log(details.isValid);         // true
log(details.validationError); // null

// Structured display map — auto-masks Aadhaar
final fields = details.toDisplayMap(maskAadhaar: true);
// {'Name': 'Ram Deva', 'DOB': '01/08/1994', 'Aadhaar No.': 'XXXX XXXX 2356', ...}

// Face photo
if (details.hasPhoto) {
  Image.memory(details.photoBytes!);
}
```

### Document Number Validation

```dart
// Standalone validation — no OCR needed
DocumentNumberValidator.isValidAadhaar('5399 8956 2356'); // true/false
DocumentNumberValidator.validateAadhaar('0000 0000 0000'); // "Aadhaar cannot start with 0"
DocumentNumberValidator.isValidPAN('ABCPD1234F'); // true/false
DocumentNumberValidator.validatePAN('ABCXD1234F'); // "PAN 4th character is invalid holder type"

// Also supports:
DocumentNumberValidator.isValidPassport('A1234567');
DocumentNumberValidator.isValidDrivingLicense('KA0120190001234');
DocumentNumberValidator.isValidVoterId('IBW0643130');
DocumentNumberValidator.isValidIFSC('SBIN0001234');
DocumentNumberValidator.isValidAccountNumber('12345678901');
```

### Document Details Parsing

```dart
// Aadhaar
final aadhaar = AadhaarDetails.fromText(result.text);
log(aadhaar.name);          // "Ram Deva"
log(aadhaar.fatherName);    // "Shiv Kumar"
log(aadhaar.dob);           // "01/08/1994"
log(aadhaar.gender);        // "Male"
log(aadhaar.aadhaarNumber); // "5399 8956 2356"

// Passport
final passport = PassportDetails.fromText(result.text);
log(passport.name);
log(passport.passportNumber);
log(passport.dateOfExpiry);

// Driving License
final dl = DrivingLicenseDetails.fromText(result.text);
log(dl.licenseNumber);
log(dl.validTill);

// Voter ID
final voter = VoterIdDetails.fromText(result.text);
log(voter.name);
log(voter.epicNumber);

// Cheque
final cheque = ChequeDetails.fromText(result.text);
log(cheque.ifscCode);
log(cheque.accountNumber);
```

### Face Extraction

```dart
// Extract face from document image
final faceBytes = await OcrDocumentSaver.extractFace(imageBytes);
if (faceBytes != null) {
  Image.memory(faceBytes);
}

// Check platform support
if (OcrDocumentSaver.isFaceExtractionSupported) {
  // Android, iOS, macOS only
}
```

### Document Viewer

```dart
OcrDocumentViewer.show(
  context,
  result: result,
  originalBytes: processedBytes,
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

// Download processed bytes with watermark
final file = await OcrDocumentSaver.downloadBytes(
  imageBytes: processedBytes,
  watermark: watermark,
);

// Or from file path (uses original file)
final file = await OcrDocumentSaver.downloadFromPath(
  result: result,
  originalImagePath: imagePath,
  watermark: watermark,
);
```

### Image Compression

```dart
// JPEG with quality (default 90)
final file = await OcrDocumentSaver.downloadBytes(
  imageBytes: processedBytes,
  imageQuality: 70,
);

// PNG lossless
final file = await OcrDocumentSaver.downloadBytes(
  imageBytes: processedBytes,
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

## Complete Example Flow

```dart
Future<void> processDocument(File file) async {
  // 1. Handle PDF or image
  final rawBytes = await file.readAsBytes();
  final Uint8List imageBytes;
  if (file.path.toLowerCase().endsWith('.pdf')) {
    final rendered = await OcrDocumentSaver.renderPdfPage(rawBytes);
    if (rendered == null) return;
    imageBytes = rendered;
  } else {
    imageBytes = rawBytes;
  }

  // 2. Auto-correct orientation
  final corrected = await OcrDocumentSaver.correctOrientation(imageBytes);

  // 3. Crop (with rotate option)
  final cropped = await OcrImageCropper.show(context, imageBytes: corrected);
  if (cropped == null) return;

  // 4. OCR
  final reader = OcrReader(validateDocument: true, maskAadhaar: true);
  final result = await reader.readFromBytes(cropped);

  // 5. Get unified details (parses fields + extracts face)
  final details = await DocumentDetails.fromResult(result, imageBytes: cropped);

  // 6. Display
  final fields = details.toDisplayMap(maskAadhaar: true);

  // 7. Download with watermark
  await OcrDocumentSaver.downloadBytes(
    imageBytes: cropped,
    watermark: OcrWatermark(lines: {'Agent': 'Ram Kumar'}),
  );
}
```

## Architecture

```
lib/
├── flutter_ocr_native.dart               # Public barrel export
└── src/
    ├── models/
    │   ├── aadhaar_details.dart            # AadhaarDetails parser
    │   ├── cheque_details.dart             # ChequeDetails parser
    │   ├── document_details.dart           # Unified DocumentDetails model
    │   ├── driving_license_details.dart    # DrivingLicenseDetails parser
    │   ├── ocr_exception.dart             # EmptyImageException, HandwrittenTextException
    │   ├── ocr_result.dart                # OcrResult, TextBlock, TextLine, TextElement
    │   ├── ocr_watermark.dart             # OcrWatermark config
    │   ├── passport_details.dart           # PassportDetails parser
    │   └── voter_id_details.dart           # VoterIdDetails parser
    ├── utils/
    │   └── ocr_document_saver.dart        # Download, save, watermark, compress, face, orientation, PDF
    ├── validators/
    │   ├── document_number_validator.dart  # Aadhaar, PAN, Passport, DL, Voter ID, IFSC validation
    │   ├── document_type_detector.dart    # Auto-detect document type from OCR text
    │   └── ocr_validator.dart             # Document validation (printed check, min length)
    ├── widgets/
    │   ├── ocr_capture_instructions.dart   # Pre-scan tips widget
    │   ├── ocr_details_card.dart          # Structured details card widget
    │   ├── ocr_document_viewer.dart       # Full-screen viewer with zoom
    │   └── ocr_image_cropper.dart         # Crop + rotate widget
    ├── ocr_platform_interface.dart         # Abstract platform contract
    ├── ocr_method_channel.dart             # MethodChannel implementation
    └── ocr_reader.dart                    # Public API class

android/src/main/kotlin/com/flutter_ocr_native/
    └── OcrPlugin.kt                       # ML Kit OCR + face + orientation + crop + rotate + PDF

ios/Classes/
    └── OcrPlugin.swift                    # Vision OCR + face + orientation + crop + rotate + PDF

macos/Classes/
    └── OcrPlugin.swift                    # Vision OCR + face + orientation + crop + rotate + PDF

windows/
    └── ocr_plugin.cpp                     # WinRT OCR + GDI+ + PDF

linux/
    └── ocr_plugin.cc                      # Tesseract OCR + Leptonica
```

## Supported Platforms

| Platform | Min Version | OCR Engine | Face Extraction | Auto-Orientation | PDF Render |
|----------|-------------|------------|-----------------|------------------|------------|
| Android  | SDK 21      | Google ML Kit | ✅ | ✅ | ✅ |
| iOS      | 13.0        | Apple Vision  | ✅ | ✅ | ✅ |
| macOS    | 10.15       | Apple Vision  | ✅ | ✅ | ✅ |
| Windows  | 10          | WinRT OCR     | ❌ | ❌ | ✅ |
| Linux    | Any         | Tesseract OCR | ❌ | ❌ | ❌ |

## Flutter Compatibility

Requires Flutter 3.19.0+ (Dart SDK >=3.2.4 <4.0.0)

## License

MIT License — see [LICENSE](LICENSE) for details.
