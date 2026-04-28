## 0.0.3

* Added `OcrWatermark` — configurable watermark text below document (Lead ID, Lat, Long, etc.)
* Added `OcrDocumentViewer` — full-screen viewer widget with pinch-to-zoom and watermark support
* Added `OcrDocumentSaver` — save document image with watermark burned in
* Watermark included in both viewer and downloaded image
* Save from viewer captures watermark in the exported image

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