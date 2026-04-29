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
