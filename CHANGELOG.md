## 0.3.6

### Bug Fixes

* **iOS tamper detection config now passed from Dart** — `isAppTampered()` in `OcrPlugin.swift` previously had a hardcoded `expectedBundleId` placeholder that required editing the native file. It now accepts the value from Dart via `expectedPackage` — same param, zero native edits on both platforms
  - `isDeviceJailbroken()` updated to accept and forward `expectedBundleId` param
  - `isAppTampered()` updated to accept `expectedBundleId` param — bundle ID check skipped if `nil` (safe default for development)
  - Removed `TODO` comment and hardcoded `"com.yourcompany.yourapp"` placeholder from `OcrPlugin.swift`
  - `expectedPackage` in `checkDeviceSecurity()` now configures both Android (package name) and iOS (bundle ID) from a single Dart call

## 0.3.5

### Improvements

* **Tamper detection config moved to Dart (Android)** — package users no longer need to edit `OcrPlugin.kt` to configure tamper detection. All three check values are now passed from Dart via `checkDeviceSecurity()`:
  - `expectedCertHash` — SHA-256 of your release signing certificate (Android)
  - `expectedPackage` — your app's package name (Android) / bundle ID (iOS)
  - `checkInstaller` — set `true` in production to block sideloaded APKs (Android)
  - All params are optional — omitting any one skips that check; safe to call with no params during development
  - `OcrPlatformInterface.isDeviceCompromised()` and `OcrMethodChannel.isDeviceCompromised()` updated to accept and forward the same params
  - `isDeviceRooted()` and `isAppTampered()` in `OcrPlugin.kt` updated to accept params instead of hardcoded config vars — no more `TODO` placeholders in native code

## 0.3.4

### Security

* **App tamper detection** — verifies the app binary has not been repackaged, resigned, or modified after publishing
  - **Android** (`OcrPlugin.kt`): `isAppTampered()` added and wired into `isDeviceRooted()`
    - Check 1: Signing certificate SHA-256 must match the release keystore hash hardcoded at build time — catches any repackaged APK (attacker must resign with their own key → hash mismatch)
    - Check 2: Package name must match expected value — catches cloned apps with a different package ID
    - Check 3: Installer source must be `com.android.vending` (Google Play Store) — catches APKs sideloaded via ADB, WhatsApp, Telegram, or third-party stores (controlled by `CHECK_INSTALLER` flag, default `false` for development)
    - All checks fail-open — wrapped in `try/catch` to prevent false positives on edge-case devices
  - **iOS** (`OcrPlugin.swift`): `isAppTampered()` added and wired into `isDeviceJailbroken()`
    - Check 1: `embedded.mobileprovision` must NOT exist — App Store builds never contain it; enterprise-resigned or Ad Hoc cracked IPAs always do
    - Check 2: Bundle ID must match expected value — catches cloned apps with a modified bundle identifier
    - Dynamic library injection (Frida/Cycript) already covered by existing `checkDynamicLibraries()` which runs before `isAppTampered()` in the same chain
    - Simulator always returns `false` via `#if targetEnvironment(simulator)` compile-time flag — unchanged
  - **Dart** (`ocr_integrity.dart`): `DeviceSecurityResult` reason string updated to mention tampering alongside root/jailbreak
  - All checks run inside the existing `OcrIntegrity.checkDeviceSecurity()` gate at app startup — zero UX impact, zero performance impact
  - `flutter analyze --no-fatal-infos` → No issues found

* **iOS jailbreak detection false positive fix** — removed paths that exist on stock iOS 15+ devices
  - Removed `/bin/bash` and `/bin/sh` from `checkJailbreakFiles()` — Apple restored these on iOS 15+ for their own tooling; present on every modern non-jailbroken device
  - Removed `/usr/libexec`, `/usr/share`, `/usr/arm-apple-darwin9`, `/usr/include` from `checkSymbolicLinks()` — these are stock iOS symlinks, not jailbreak indicators
  - `checkSymbolicLinks()` now only checks `/Applications`, `/Library/Ringtones`, `/Library/Wallpaper`

* **Android BlueStacks detection** — replaced unreliable build prop string matching with filesystem-based detection
  - BlueStacks 5+ spoofs build properties to look like real Samsung/Pixel devices — string matching on `Build.FINGERPRINT` / `Build.MANUFACTURER` was unreliable
  - `isEmulator()` now checks 4 BlueStacks-specific filesystem paths (`/data/data/com.bluestacks.home`, `/data/data/com.bluestacks.settings`, `/mnt/windows/BstSharedFolder`, `/data/bluestacks.prop`) and package `com.bluestacks.home` — these exist regardless of build prop spoofing
  - Standard AOSP emulator signals (goldfish/ranchu hardware, generic fingerprint, Genymotion) retained as fallback

### Documentation

* Added `TAMPER_DETECTION.md` — full technical and manager-facing document covering:
  - What tamper detection is and why KYC apps are high-value targets
  - How the SHA-256 certificate hash works and why it cannot be faked
  - Threat coverage matrix (root vs jailbreak vs tamper)
  - Step-by-step runtime execution flow from `main()` to block/pass decision
  - Implementation notes with exact code for all 3 files changed
  - Configuration flags and one-time production setup instructions
  - All known attack bypass techniques and countermeasures
  - Recommended additional hardening (Play Integrity API, App Attest, ProGuard)

## 0.3.3

### Improvements

* **Old & new document format support** — all parsers now handle both legacy and current Indian document layouts:
  - **Aadhaar**: new bilingual format (`नाम / Name`, `पिता का नाम / Father's Name`, `जन्म की तारीख / DOB`, `पता / Address`) detected alongside old English-only labels. DOB value on next line supported
  - **PAN**: bilingual layout already supported from 0.3.1 — no change
  - **Driving License**: new smart card format (`COV`, `DOI`, `NT VALIDITY`, `NON-TRANSPORT` validity dates on separate lines) + improved DL number regex covering all Indian state formats including 6-digit serial and compact no-separator variants
  - **Voter ID**: new format (`Name:`, `Father's Name:`, `Husband's Name:`, `Sex:`, `Age:`) parsed alongside old `ELECTOR'S NAME` / `FATHER'S NAME` format. `Age` field converted to approximate birth year when full DOB is absent. `M`/`F` single-char gender values normalised to `Male`/`Female`
  - **Passport**: MRZ (Machine Readable Zone) parsing added — `P<IND<SURNAME<<GIVEN` and digit line parsed to extract surname, given name, nationality, DOB, gender, expiry and passport number directly from MRZ. MRZ date `YYMMDD` converted to `DD/MM/YYYY` with correct century. Old labeled-field booklet format unchanged
  - **Cheque**: new CTS printed format — `A/C No.`, `Account No.`, `Acc No.`, `Account Number` label patterns parsed before falling back to raw digit scanning. Account number on next line after label also handled

* **Smart handwriting detection** — per-document-type policy prevents false rejections:
  - **Passport** and **Cheque** and **Driving License** use `allowMixed` policy — only rejected if zero printed keywords found (truly blank handwritten paper). Signatures on passports and handwritten amounts/payees on cheques no longer cause `HandwrittenTextException`
  - **Aadhaar**, **PAN**, **Voter ID** keep strict `rejectIfHandwritten` policy — fully handwritten documents correctly rejected
  - `docType` hint parameter added to all `OcrReader` read methods (`readFromPath`, `readFromBytes`, `readFromFile`, `readFromPdf`, `readFromPdfFile`) — pass known type to skip auto-detection and apply correct policy immediately

* **Document type detector** — passport MRZ scoring added: `P<IND<` pattern scores +5, MRZ digit line pattern scores +5 — ensures MRP passports detected even without the word "PASSPORT" in OCR text

* **API surface reduced** — package now exports only what app developers need:
  - **Removed from public API**: `OcrPlatformInterface`, `OcrMethodChannel` (internal channel wiring), `AadhaarDetails`, `ChequeDetails`, `DrivingLicenseDetails`, `PassportDetails`, `VoterIdDetails` (use `DocumentDetails` instead), `OcrException` base class (catch `EmptyImageException` / `HandwrittenTextException` directly), `OcrDetailsCard`, `VoterIdDetailsCard` (build UI from `DocumentDetails.toDisplayMap()`), `HandwritingPolicy` (internal enum)
  - All removed classes still exist in the package source and are used internally — only their re-export from the barrel is removed

* **`DocumentDetails` internal refactor** — removed redundant `_parse()` indirection; `fromResultSync` now owns the dispatch switch directly. `_hasPhoto` helper inlined. `fromText` simplified to single expression


### Bug Fixes

* **Fixed `NOT_INITIALIZED` crash on re-upload (Android, Windows, Linux)** — scanning a second image after the first scan threw `PlatformException(NOT_INITIALIZED, Recognizer not initialized)`
  - **Android**: `processImage()` now lazily recreates `TextRecognizer` if null — seamless re-use after `dispose()`
  - **Windows**: `RecognizeFromBytes()` now lazily recreates `OcrEngine` if null — recovers from failed init or unexpected null state
  - **Linux**: `recognize()` now lazily reinitializes `TessBaseAPI` if null — recovers from failed init or dispose
  - **iOS/macOS**: unaffected — Vision framework creates a fresh `VNRecognizeTextRequest` per call with no persistent state

## 0.3.1

### Bug Fixes

* **Critical PAN detection fix (Android, iOS, macOS)** — bilingual PAN cards (Hindi + English) with no-vowel PAN numbers like `BWPPM8548F` were silently dropped by the `isEnglish()` filter
  - Root cause: vowel check `letters.count >= 4 && !hasVowel` incorrectly rejected valid PAN tokens that contain no vowels (e.g. `BWPPM`, `BWPPMF`)
  - Fix applied to all three Vision/ML Kit platforms: **Android** (`OcrPlugin.kt`), **iOS** (`OcrPlugin.swift`), **macOS** (`OcrPlugin.swift`)
  - Any token containing digits (IDs, codes, PAN numbers, dates) now always passes through the English filter
  - Vowel check now only applies to pure-letter strings of 5+ characters (rejects Hindi/non-Latin words)
  - Threshold raised from 4 → 5 letters to avoid rejecting short English abbreviations (`DEPT`, `GOVT`, `CARD`)
  - Windows (WinRT) and Linux (Tesseract) were unaffected — their `isEnglish` only checks for `[A-Za-z0-9]` presence with no vowel filter
  - PAN cards with vowels in the number (e.g. `AXEPN1010E`) were unaffected on all platforms
* **PAN extraction — space-tolerant matching** — `extractPAN()` now handles OCR splitting PAN into `BWPPM 8548F` (space between letter-block and digit-block)
  - Added Strategy 2: `([A-Z]{5})\s+(\d{4})\s*([A-Z])` pattern
  - Added Strategy 3: OCR misread correction (O→0, I→1, S→5) with space tolerance
  - Added Strategy 4: relaxed 4th-char fallback for OCR-misread holder type character
* **PAN name/father parsing — bilingual layout** — `_fromPan()` now correctly extracts name and father name from bilingual cards where Hindi labels are stripped to `/ Name`, `/ Father's Name`
  - Added `_extractNameValue()` helper — checks text after `/` on same line first, then next line
  - Handles both old format (name on next line after label) and new bilingual format (label + value on same line separated by `/`)
* **Raw OCR text copy button** — example app now shows a copy icon on the Raw OCR Text card for easy debugging


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
