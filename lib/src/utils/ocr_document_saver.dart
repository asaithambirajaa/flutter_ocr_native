import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr_result.dart';
import '../models/ocr_watermark.dart';

/// Output image format for saving.
enum OcrImageFormat {
  /// JPEG — smaller file size, configurable quality. Default.
  jpeg,

  /// PNG — lossless, larger file size.
  png,
}

class OcrDocumentSaver {
  static const _channel =
      MethodChannel('com.flutter_ocr_native/text_recognition');

  /// Renders a single PDF page to image bytes (JPEG).
  /// [pdfBytes] — raw PDF file bytes.
  /// [page] — zero-based page index (default 0).
  /// [scale] — render scale factor (default 2.0 for high quality).
  /// Returns image bytes or null if rendering fails.
  /// Uses native PDF rendering — no third-party packages needed.
  /// - Android: PdfRenderer (API 21+)
  /// - iOS/macOS: CGPDFDocument
  /// - Windows: Windows.Data.Pdf
  /// - Linux: not supported (returns null)
  static Future<Uint8List?> renderPdfPage(
    Uint8List pdfBytes, {
    int page = 0,
    double scale = 2.0,
  }) async {
    if (Platform.isLinux) return null;
    if (pdfBytes.isEmpty) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'renderPdfPage',
        {'pdfBytes': pdfBytes, 'page': page, 'scale': scale},
      );
      // Validate that result is a valid JPEG (starts with FFD8)
      if (result != null && result.length > 2 && result[0] == 0xFF && result[1] == 0xD8) {
        return result;
      }
      return result;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the number of pages in a PDF.
  /// Returns 0 if the PDF cannot be read.
  static Future<int> getPdfPageCount(Uint8List pdfBytes) async {
    if (Platform.isLinux) return 0;
    try {
      final result = await _channel.invokeMethod<int>(
        'getPdfPageCount',
        {'pdfBytes': pdfBytes},
      );
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Renders all pages of a PDF to image bytes list.
  /// Returns a list of JPEG image bytes for each page.
  static Future<List<Uint8List>> renderAllPdfPages(
    Uint8List pdfBytes, {
    double scale = 2.0,
  }) async {
    final count = await getPdfPageCount(pdfBytes);
    final pages = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      final page = await renderPdfPage(pdfBytes, page: i, scale: scale);
      if (page != null) pages.add(page);
    }
    return pages;
  }

  /// Downloads to the platform's download folder.
  ///
  /// - [watermark] — pass to add watermark, omit or null for no watermark
  /// - [imageQuality] — JPEG quality 1-100 (default 90). Ignored for PNG
  /// - [format] — output format. Default JPEG
  static Future<File> download({
    required OcrResult result,
    required Uint8List originalImageBytes,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    final dir = await _getDownloadDirectory();
    final imageBytes =
        result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    return _process(imageBytes, dir, fileName, watermark, imageQuality, format);
  }

  /// Downloads from a file path. Auto-detects format from file extension.
  static Future<File> downloadFromPath({
    required OcrResult result,
    required String originalImagePath,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat? format,
  }) async {
    final originalBytes = await File(originalImagePath).readAsBytes();
    return download(
      result: result,
      originalImageBytes: originalBytes,
      fileName: fileName,
      watermark: watermark,
      imageQuality: imageQuality,
      format: format ?? _formatFromPath(originalImagePath),
    );
  }

  /// Saves raw bytes to the platform's download folder.
  static Future<File> downloadBytes({
    required Uint8List imageBytes,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    final dir = await _getDownloadDirectory();
    return _process(imageBytes, dir, fileName, watermark, imageQuality, format);
  }

  /// Saves to a specific [directory].
  static Future<File> save({
    required OcrResult result,
    required Uint8List originalImageBytes,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    final imageBytes =
        result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    return _process(
        imageBytes, directory, fileName, watermark, imageQuality, format);
  }

  /// Saves from a file path to a specific [directory].
  static Future<File> saveFromPath({
    required OcrResult result,
    required String originalImagePath,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat? format,
  }) async {
    final originalBytes = await File(originalImagePath).readAsBytes();
    return save(
      result: result,
      originalImageBytes: originalBytes,
      directory: directory,
      fileName: fileName,
      watermark: watermark,
      imageQuality: imageQuality,
      format: format ?? _formatFromPath(originalImagePath),
    );
  }

  /// Burns watermark into image bytes using native platform rendering.
  static Future<Uint8List> burnWatermark(
    Uint8List imageBytes,
    OcrWatermark watermark, {
    int quality = 90,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'burnWatermark',
      {'imageBytes': imageBytes, 'lines': watermark.lines, 'quality': quality},
    );
    return result ?? imageBytes;
  }

  /// Compresses image bytes using native JPEG compression.
  /// Accepts any input format (JPEG, PNG, WEBP, BMP, HEIC, etc.)
  /// [quality] — 1 (smallest) to 100 (best). Default 80.
  static Future<Uint8List> compressImage(
    Uint8List imageBytes, {
    int quality = 80,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'compressImage',
      {'imageBytes': imageBytes, 'quality': quality},
    );
    return result ?? imageBytes;
  }

  /// Extracts the face/photo from a document image (Aadhaar, PAN, etc.)
  /// Uses native face detection (ML Kit on Android, Vision on iOS/macOS).
  /// Returns cropped face image bytes, or null if no face found.
  ///
  /// Supported: Android, iOS, macOS.
  /// Windows/Linux: returns null (face detection not available).
  static Future<Uint8List?> extractFace(Uint8List imageBytes) async {
    if (Platform.isWindows || Platform.isLinux) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'extractFace',
        {'imageBytes': imageBytes},
      );
      return result;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Extracts face from a file path.
  /// Returns null if no face found or platform not supported.
  static Future<Uint8List?> extractFaceFromPath(String imagePath) async {
    if (Platform.isWindows || Platform.isLinux) return null;
    final bytes = await File(imagePath).readAsBytes();
    return extractFace(bytes);
  }

  /// Whether face extraction is supported on the current platform.
  static bool get isFaceExtractionSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Corrects image orientation based on EXIF data.
  /// Returns the image bytes with correct upright orientation.
  /// On Windows/Linux, returns the original bytes unchanged.
  /// For PDF-rendered images, orientation correction is skipped
  /// since PDFs are already correctly oriented.
  static Future<Uint8List> correctOrientation(Uint8List imageBytes) async {
    if (Platform.isWindows || Platform.isLinux) return imageBytes;
    // Skip if image is too large (>10MB) to avoid OOM during multi-rotation OCR
    if (imageBytes.length > 10 * 1024 * 1024) return imageBytes;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'correctOrientation',
        {'imageBytes': imageBytes},
      );
      return result ?? imageBytes;
    } catch (_) {
      return imageBytes;
    }
  }

  static Future<File> _process(
    Uint8List imageBytes,
    Directory directory,
    String? fileName,
    OcrWatermark? watermark,
    int quality,
    OcrImageFormat format,
  ) async {
    Uint8List finalBytes = imageBytes;
    final isPng = format == OcrImageFormat.png;
    final nativeQuality = isPng ? 100 : quality;

    if (watermark != null) {
      finalBytes =
          await burnWatermark(finalBytes, watermark, quality: nativeQuality);
    } else if (!isPng) {
      finalBytes = await compressImage(finalBytes, quality: nativeQuality);
    }

    final ext = isPng ? 'png' : 'jpg';
    final name =
        fileName ?? 'ocr_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final file = File('${directory.path}/$name');
    return file.writeAsBytes(finalBytes);
  }

  static OcrImageFormat _formatFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return OcrImageFormat.png;
    return OcrImageFormat.jpeg;
  }

  static Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) return downloads;
      final external = await getExternalStorageDirectory();
      if (external != null) return external;
    } else if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final downloads = Directory('$userProfile\\Downloads');
        if (await downloads.exists()) return downloads;
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final downloads = Directory('$home/Downloads');
        if (await downloads.exists()) return downloads;
      }
    }
    return getApplicationDocumentsDirectory();
  }
}
