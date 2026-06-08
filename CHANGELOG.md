## 0.3.0

* **Native PDF to image conversion** — render PDF pages to images without any third-party Dart package
  - Android: `PdfRenderer` (API 21+)
  - iOS: `CGPDFDocument` (CoreGraphics)
  - macOS: `CGPDFDocument` (CoreGraphics)
  - Windows: `Windows.Data.Pdf` (WinRT)
  - Linux: not supported (returns null gracefully)
* Added `OcrDocumentSaver.renderPdfPage()` — renders a single PDF page to JPEG bytes
* Added `OcrDocumentSaver.getPdfPageCount()` — returns total pages in a PDF
* Added `OcrDocumentSaver.renderAllPdfPages()` — renders all pages to a list of image bytes
* Added `OcrReader.readFromPdf()` — single-call PDF to OCR text
* Added `OcrReader.readFromPdfFile()` — OCR directly from a PDF file
* **Capture instructions widget** — `OcrCaptureInstructions` shows best practices before scan/upload
  - `showAsBottomSheet()` — modal bottom sheet with tips
  - `showAsDialog()` — dialog with tips
  - Inline widget mode — embed directly in your UI
  - Customizable instructions via `OcrInstruction` model
* **Enhanced PAN card detection** — OCR misread correction (O→0, I→1, S→5), uppercase fallback, name/DOB/father name parsing
* **OOM crash fix (Android)** — `correctOrientation` now uses 1024px downscaled test bitmaps for rotation detection instead of full-size images
* **OOM crash fix (all platforms)** — PDF rendering capped at 3000px max dimension
* **Background thread rendering** — PDF rendering runs off main thread on Android, iOS, and macOS
* **Fixed `FlutterImageDecoderImplDefault` crash** — PDF bytes no longer passed to image decoder; detected and rendered to JPEG first
* **Fixed Windows compile error** — added `Windows.UI.h` include, fixed `ColorHelper` usage with direct struct
* **Fixed Windows stream crash** — `DataWriter.DetachStream()` prevents premature stream closure
* **Linux graceful fallback** — `renderPdfPage` returns null, `getPdfPageCount` returns 0 (no crash)
* Example app now supports PDF file picking and processing
* Example app shows capture instructions before camera/gallery
* Added `_isPdf()` detection in example flow
* File picker now accepts PDF alongside image formats
* `correctOrientation` skips images >10MB to prevent OOM
* **Windows compile fix** — resolves all 3 MSVC build errors:
  - Added `#define NOMINMAX` and `(std::max)(...)` parenthesization to prevent `error C2589` from Windows `max` macro
  - Replaced broad `using namespace` WinRT imports with namespace aliases (`ocr::`, `streams::`, `imaging::`, `pdf::`) to fix `error C2872: 'IUnknown' ambiguous symbol`
  - Added `#include <winrt/Windows.Globalization.h>` to fix linker error for `Windows::Globalization::Language`

## 0.2.1

* **Smart auto-orientation** — only rotates if original is unreadable; keeps already-readable images untouched
* **Cheque MICR fix** — MICR line (special font at bottom) no longer triggers handwriting rejection
* **Cheque parser rewrite** — case-insensitive IFSC extraction, spaced account numbers, 30+ bank name patterns, address extraction from branch lines
* Added `address` field to `ChequeDetails` and `DocumentDetails` for cheques
* Improved `detectPrinted` on all platforms — excludes low-confidence numeric elements at image bottom from scoring

## 0.2.0

* **Auto-orientation correction** — detects correct image rotation using OCR confidence scoring across all 4 rotations (0°, 90°, 180°, 270°). Works even without EXIF data
* **Image cropper with rotate** — added rotate button (90° clockwise) to crop UI
* **Document type auto-detection** — scores OCR text against keywords/patterns for Aadhaar, PAN, Passport, Driving License, Voter ID, Cheque
* **Unified `DocumentDetails` model** — single `fromResult()` API handles all doc types, face extraction, validation, and `toDisplayMap(maskAadhaar: true)`
* **Face extraction** — ML Kit Face Detection (Android), Vision (iOS/macOS). Returns cropped face bytes
* **Document parsers** — `PassportDetails`, `DrivingLicenseDetails`, `VoterIdDetails`, `ChequeDetails`
* **Extended validation** — Passport, Driving License, Voter ID (EPIC), IFSC, Account number
* Added `OcrDocumentSaver.correctOrientation()` — auto-corrects image orientation before display
* Added `OcrDocumentSaver.extractFace()` and `extractFaceFromPath()`
* Added `OcrDocumentSaver.isFaceExtractionSupported` getter
* Added `result.docType` and `result.docTypeLabel` getters on `OcrResult`
* Added `DocumentTypeDetector.detect()`, `.label()`, `.icon()` static methods
* Added `OcrDocumentViewer` support for `originalBytes` parameter
* Fixed Voter ID extraction — NFKD normalization for Unicode lookalike characters
* Fixed false Voter ID matches from date strings (e.g., "biRTH 15/07/199x")
* Added **macOS** platform support — Apple Vision framework
* Added **Windows** platform support — WinRT OCR engine + GDI+
* Added **Linux** platform support — Tesseract OCR + Leptonica
* Added `DocumentNumberValidator` — validates Aadhaar (Verhoeff checksum) and PAN (format + holder type)
* Added `AadhaarDetails` model — parses OCR text into structured fields
* Added `OcrDetailsCard` widget
* Fixed Aadhaar masking regex — requires separators, won't mask pincodes
* Fixed validation working on masked text — validates against raw text internally

## 0.0.7

* Added `OcrImageFormat` enum — configurable output format (JPEG or PNG)
* Added `imageQuality` parameter to all save/download methods — JPEG compression 1-100
* Added `format` parameter to all save/download methods — choose JPEG or PNG output
* `downloadFromPath` auto-detects output format from original file extension (.png → PNG, others → JPEG)
* Added `compressImage()` standalone method — compress any image bytes natively
* Accepts any input image format (JPEG, PNG, WEBP, BMP, GIF, HEIC, TIFF) — decoded natively
* Native compression via Android `Bitmap.compress` and iOS `jpegData`/`pngData`
* Watermark is now fully optional — omit or pass null to skip

## 0.0.6

* Lowered SDK constraint to `>=3.2.4 <4.0.0` (Flutter 3.19.0+) for broader compatibility
* Fixed `Color.toARGB32()` not available on older Dart versions — replaced with version-safe `_colorToArgb()` helper using `.a/.r/.g/.b` float API
* Zero deprecation warnings on all Dart 3.x versions (3.2.4 through 3.11+)

## 0.0.5

* Updated README with complete usage documentation for all features
* Added examples for Basic OCR, Validation & Aadhaar Masking, Document Viewer, Download with Watermark, Custom Validator, and Runtime Toggle
* Added full architecture tree in README covering all source files
* Added Supported Platforms table and Flutter Compatibility section
* Updated Getting Started version to `^0.0.4`

## 0.0.4

* Fixed watermark not appearing in downloaded images
* Moved watermark rendering from `dart:ui` Canvas to native platform (Android Canvas / iOS CoreGraphics) for reliable text rendering
* Added `burnWatermark` native method channel — watermark is now burned into images on the native side
* Auto-scaled watermark font size to 3% of image width (minimum 36px) — always readable regardless of image resolution
* Bold watermark text with 1.5x line height for better readability
* Added `downloadBytes()` method to `OcrDocumentSaver` for saving raw bytes directly
* Added `path_provider` as plugin dependency — platform-specific download paths handled internally
* Removed `path_provider` dependency from example app — package handles it
* Simplified `OcrDocumentViewer` save — uses native `burnWatermark` instead of unreliable `RepaintBoundary` capture

## 0.0.3

* Added `OcrWatermark` model — configurable watermark with key-value lines (Lead ID, Lat, Long, Agent, Date, etc.), customizable text color, background color, font size, and padding
* Added `OcrDocumentViewer` widget — full-screen document viewer with pinch-to-zoom (0.5x–5x), watermark overlay below image, configurable save button, and `OcrDocumentViewer.show()` for one-liner navigation
* Added `OcrDocumentSaver` utility — saves masked/original image to file with watermark burned into the image using Canvas, supports save from file path or raw bytes
* Viewer save captures the watermark in the exported image via `RepaintBoundary`
* Updated example app with View and Download buttons using the new package utilities

## 0.0.2

* Renamed package from `ocr` to `flutter_ocr_native`
* Lowered SDK constraint to support Flutter 3.27.1+
* Fixed Aadhaar image masking for different card positions and orientations
* Improved handwriting detection using ML Kit confidence signals
* Added `maskedImageBytes` — image with Aadhaar digits blacked out
* Added `hasAadhaar` getter on `OcrResult`

## 0.0.1

* Initial release
* On-device OCR using ML Kit (Android) and Vision framework (iOS)
* English-only text extraction — non-Latin scripts auto-filtered
* Structured results: blocks → lines → elements with bounding boxes & confidence
* Aadhaar number masking (text + image) — configurable
* Handwriting detection — rejects non-printed documents
* Empty/blank image detection
