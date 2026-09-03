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
- **Old & new document format support** — all parsers handle both legacy and current Indian document layouts
- **MRZ passport parsing** — extracts all fields directly from Machine Readable Zone lines
- **Unified `DocumentDetails` model** — single API for all document types
- Aadhaar number masking (text + image) — configurable
- Aadhaar & PAN number validation (Verhoeff checksum, format check)
- **Bilingual document support** — Hindi + English labels (`नाम / Name`, `पिता का नाम / Father's Name`) on Aadhaar and PAN
- Passport, Driving License, Voter ID, IFSC, Account number validation
- **Face extraction** from document images (Android, iOS, macOS)
- **Smart handwriting detection** — per-document-type policy; passport signatures and cheque handwriting no longer cause false rejections
- **Device & app security** — root detection, jailbreak detection, emulator detection, app tamper detection
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
  flutter_ocr_native: ^0.3.6
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
final corrected = await OcrDocumentSaver.correctOrientation(imageBytes);
final result = await reader.readFromBytes(corrected);
```

### Image Cropper with Rotate

```dart
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
OcrCaptureInstructions()
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

### Smart Handwriting Detection

Documents that always contain handwritten fields (passport signature, cheque amount/payee,
old-format driving license entries) are handled with a mixed-mode policy — only rejected
if the document contains **zero** printed keywords at all.

```dart
final reader = OcrReader(validateDocument: true);

// Hint the document type to apply the correct policy immediately
// Passport: signature won't cause HandwrittenTextException
final result = await reader.readFromBytes(
  passportBytes,
  docType: DetectedDocType.passport,
);

// Cheque: handwritten amount/payee won't cause HandwrittenTextException
final result = await reader.readFromBytes(
  chequeBytes,
  docType: DetectedDocType.cheque,
);

// Aadhaar/PAN/Voter ID: strict — fully handwritten document is rejected
final result = await reader.readFromBytes(
  aadhaarBytes,
  docType: DetectedDocType.aadhaar,
);
```

| Document | Policy | Behaviour |
|---|---|---|
| Aadhaar, PAN, Voter ID | Strict | Rejected if native says not printed |
| Passport, Cheque, DL | Mixed | Only rejected if zero printed keywords found |

### Document Type Auto-Detection

```dart
final result = await reader.readFromBytes(imageBytes);

log(result.docType);      // DetectedDocType.aadhaar
log(result.docTypeLabel); // "Aadhaar Card"
```

### Unified Document Details

Single API for all document types — handles old format, new bilingual format, and MRZ passports.

```dart
final details = await DocumentDetails.fromResult(
  result,
  imageBytes: processedBytes,
);

log(details.docType);         // DetectedDocType.aadhaar
log(details.documentNumber);  // "5399 8956 2356"
log(details.name);            // "Ram Deva"
log(details.dob);             // "01/08/1994"
log(details.isValid);         // true
log(details.validationError); // null

// Structured display map — auto-masks Aadhaar
final fields = details.toDisplayMap(maskAadhaar: true);
// {'Document No.': 'XXXX XXXX 2356', 'Name': 'Ram Deva', 'DOB': '01/08/1994', ...}

// Face photo (Aadhaar, PAN, Passport, DL, Voter ID)
if (details.hasPhoto) {
  Image.memory(details.photoBytes!);
}

// Synchronous (no face extraction)
final details = DocumentDetails.fromResultSync(result);

// From raw text
final details = DocumentDetails.fromText(ocrText, DetectedDocType.passport);
```

### Document Number Validation

```dart
// Standalone validation — no OCR needed
DocumentNumberValidator.isValidAadhaar('5399 8956 2356'); // true/false
DocumentNumberValidator.validateAadhaar('0000 0000 0000'); // "Aadhaar cannot start with 0"
DocumentNumberValidator.isValidPAN('ABCPD1234F'); // true/false
DocumentNumberValidator.validatePAN('ABCXD1234F'); // "PAN 4th character is invalid holder type"

DocumentNumberValidator.isValidPassport('A1234567');
DocumentNumberValidator.isValidDrivingLicense('KA0120190001234');
DocumentNumberValidator.isValidVoterId('IBW0643130');
DocumentNumberValidator.isValidIFSC('SBIN0001234');
DocumentNumberValidator.isValidAccountNumber('12345678901');
```

### Face Extraction

```dart
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

final file = await OcrDocumentSaver.downloadBytes(
  imageBytes: processedBytes,
  watermark: watermark,
);

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

// Standalone compress
final compressed = await OcrDocumentSaver.compressImage(anyImageBytes, quality: 60);
```

### Custom Validator

```dart
final reader = OcrReader(
  validateDocument: true,
  validator: OcrValidator(minTextLength: 20),
);
```

### Device & App Security

Blocks KYC on rooted devices, jailbroken iPhones, emulators, BlueStacks, and tampered/repackaged app binaries.
Runs at app startup before any KYC screen loads — zero UX impact.

```dart
// Development — no config needed, all tamper checks are skipped
final security = await OcrIntegrity.checkDeviceSecurity();
if (!security.secure) {
  // security.reason explains why — show blocked screen
  return;
}

// Production — pass your values from Dart, no native file edits needed
final security = await OcrIntegrity.checkDeviceSecurity(
  expectedCertHash: 'A1:B2:C3:...',    // SHA-256 of your release keystore
  expectedPackage: 'com.yourcompany.app',
  checkInstaller: true,                 // blocks sideloaded APKs
);
```

| Signal | Android | iOS |
|---|---|---|
| Rooted device | ✅ su binary, dangerous apps, rw paths, test-keys | — |
| Jailbroken device | — | ✅ Cydia, sandbox violation, dylib injection, symlinks |
| Emulator / BlueStacks | ✅ filesystem + build signals | ✅ simulator flag |
| Repackaged APK / IPA | ✅ cert hash + package name + installer source | ✅ MobileProvision + bundle ID + dylib injection |

**`expectedPackage` works for both platforms** — Android uses it as the package name, iOS uses it as the bundle ID. One Dart call configures both.

**Android — generate your release cert hash:**

```bash
keytool -list -v -keystore release.keystore -alias <your_alias>
# Copy the SHA-256 fingerprint and pass it as expectedCertHash above
```

See [TAMPER_DETECTION.md](TAMPER_DETECTION.md) for full documentation, attack bypass analysis, and recommended additional hardening.

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

  // 4. OCR — hint doc type for correct handwriting policy
  final reader = OcrReader(validateDocument: true, maskAadhaar: true);
  final result = await reader.readFromBytes(
    cropped,
    docType: DetectedDocType.aadhaar, // optional — auto-detected if omitted
  );

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

## Public API

```
OcrReader                      readFromPath / readFromBytes / readFromFile
                               readFromPdf / readFromPdfFile
                               validateDocument, maskAadhaar, validator

OcrResult                      text, blocks, isPrinted, hasAadhaar,
TextBlock / TextLine           maskedImageBytes, docType, docTypeLabel
TextElement

DocumentDetails                fromResult() / fromResultSync() / fromText()
                               docType, documentNumber, name, fatherName,
                               dob, gender, address, isValid, validationError,
                               photoBytes, extraFields, toDisplayMap()

OcrDocumentSaver               renderPdfPage / getPdfPageCount / renderAllPdfPages
                               correctOrientation / extractFace
                               download / downloadBytes / downloadFromPath
                               save / saveFromPath / burnWatermark / compressImage

DocumentNumberValidator        isValidAadhaar / validateAadhaar
                               isValidPAN / validatePAN / panHolderType
                               isValidPassport / isValidDrivingLicense
                               isValidVoterId / isValidIFSC / isValidAccountNumber
                               extractAadhaar / extractPAN / extractPassport
                               extractDrivingLicense / extractVoterId / extractIFSC

DocumentTypeDetector           detect() / label() / icon()
DetectedDocType                aadhaar / pan / passport / drivingLicense
                               voterId / cheque / unknown

OcrValidator                   validate(result, docType)
OcrWatermark                   lines, textColor, backgroundColor, fontSize
OcrImageFormat                 jpeg / png

OcrIntegrity                   checkDeviceSecurity() → DeviceSecurityResult
                               hashDetails / hashImage
                               checkImageQuality / checkConfidence
                               consistencyErrors / verify
                               persistAuditRecord / persistTamperEvent
DeviceSecurityResult           secure, reason
OcrAuditRecord                 create() / fromJson() / toJson()
OcrVerificationResult          passed, reason
TamperEvent                    fromVerification() / toJson()

EmptyImageException            thrown when no text detected
HandwrittenTextException       thrown when document is fully handwritten

OcrCaptureInstructions         showAsBottomSheet() / showAsDialog() / inline widget
OcrInstruction                 icon, title, description, color
OcrImageCropper                show() — full-screen crop + rotate
OcrDocumentViewer              show() — full-screen viewer with zoom + save
```

## Architecture

```
lib/
├── flutter_ocr_native.dart               # Public barrel export
└── src/
    ├── models/
    │   ├── aadhaar_details.dart            # internal — AadhaarDetails parser
    │   ├── cheque_details.dart             # internal — ChequeDetails parser
    │   ├── document_details.dart           # DocumentDetails (public unified model)
    │   ├── driving_license_details.dart    # internal — DrivingLicenseDetails parser
    │   ├── ocr_exception.dart              # EmptyImageException, HandwrittenTextException
    │   ├── ocr_result.dart                 # OcrResult, TextBlock, TextLine, TextElement
    │   ├── ocr_watermark.dart              # OcrWatermark config
    │   ├── passport_details.dart           # internal — PassportDetails parser (+ MRZ)
    │   └── voter_id_details.dart           # internal — VoterIdDetails parser
    ├── utils/
    │   └── ocr_document_saver.dart         # Download, save, watermark, compress, face, orientation, PDF
    ├── security/
    │   └── ocr_integrity.dart              # Device security, tamper detection, audit trail, hashing
    ├── validators/
    │   ├── document_number_validator.dart  # Aadhaar, PAN, Passport, DL, Voter ID, IFSC validation
    │   ├── document_type_detector.dart     # Auto-detect document type from OCR text
    │   └── ocr_validator.dart              # Document validation (printed check, min length)
    ├── widgets/
    │   ├── ocr_capture_instructions.dart   # Pre-scan tips widget
    │   ├── ocr_details_card.dart           # internal — details card widget
    │   ├── ocr_document_viewer.dart        # Full-screen viewer with zoom
    │   ├── ocr_image_cropper.dart          # Crop + rotate widget
    │   └── voter_id_details_card.dart      # internal — Voter ID card widget
    ├── ocr_platform_interface.dart         # internal — abstract platform contract
    ├── ocr_method_channel.dart             # internal — MethodChannel implementation
    └── ocr_reader.dart                     # OcrReader public API

android/src/main/kotlin/com/flutter_ocr_native/
    └── OcrPlugin.kt                        # ML Kit OCR + face + orientation + crop + rotate + PDF

ios/Classes/
    └── OcrPlugin.swift                     # Vision OCR + face + orientation + crop + rotate + PDF

macos/Classes/
    └── OcrPlugin.swift                     # Vision OCR + face + orientation + crop + rotate + PDF

windows/
    └── ocr_plugin.cpp                      # WinRT OCR + GDI+ + PDF

linux/
    └── ocr_plugin.cc                       # Tesseract OCR + Leptonica
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
