## 0.1.0

* Added **macOS** platform support — Apple Vision framework (same as iOS)
* Added **Windows** platform support — WinRT OCR engine + GDI+ for image processing
* Added **Linux** platform support — Tesseract OCR + Leptonica
* Added `DocumentNumberValidator` — validates Aadhaar (Verhoeff checksum) and PAN (format + holder type)
* Added `validateAadhaar()` and `validatePAN()` methods returning exact error messages
* Added `result.isAadhaarValid`, `result.isPanValid`, `result.aadhaarError`, `result.panError` getters on `OcrResult`
* Added `result.panHolderType` — returns "Individual", "Company", "HUF", etc.
* Added `AadhaarDetails` model — parses OCR text into structured fields (Name, Father/Husband, DOB, Gender, Address, Aadhaar No.)
* Added `OcrDetailsCard` widget — displays parsed fields in a structured card layout
* Fixed Aadhaar masking regex — now requires separators between digit groups, won't mask pincodes or names
* Fixed validation working on masked text — now validates against original unmasked text internally
* Added `file_picker` support in example app for desktop platforms
* Example app adapts UI for mobile (camera/gallery) vs desktop (file browser, sidebar layout)
* Download path support for macOS (`~/Downloads`) and Linux (`~/Downloads`)

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
