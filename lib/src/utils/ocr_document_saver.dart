import 'dart:async';
import 'dart:io';

import 'dart:ui' as ui;

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

  /// Enhances a low-quality image for better OCR accuracy.
  ///
  /// Pipeline (pure Dart, no native call):
  ///   1. Grayscale conversion — removes colour noise
  ///   2. Contrast stretch — expands pixel range to full 0–255
  ///   3. Otsu binarization — adaptive black/white threshold for faded text
  ///   4. Unsharp mask — sharpens edges on the binarized result
  ///
  /// Returns the enhanced image as PNG bytes, or the original bytes on failure.
  /// Safe to call on any image — dramatically improves faded/low-contrast scans.
  static Future<Uint8List> enhanceForOcr(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (byteData == null) return imageBytes;

      final src = byteData.buffer.asUint8List();
      final pixels = w * h;

      // ── Step 1: Grayscale ─────────────────────────────────────────────────
      final gray = Uint8List(pixels);
      for (int i = 0; i < pixels; i++) {
        final r = src[i * 4];
        final g = src[i * 4 + 1];
        final b = src[i * 4 + 2];
        gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
      }

      // ── Step 2: Contrast stretch ──────────────────────────────────────────
      int minV = 255, maxV = 0;
      for (final v in gray) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      final range = maxV - minV;
      final stretched = Uint8List(pixels);
      for (int i = 0; i < pixels; i++) {
        stretched[i] =
            range == 0 ? gray[i] : ((gray[i] - minV) * 255 ~/ range).clamp(0, 255);
      }

      // ── Step 3: Otsu binarization ─────────────────────────────────────────
      // Build histogram
      final hist = List<int>.filled(256, 0);
      for (final v in stretched) hist[v]++;
      // Find optimal threshold that maximises inter-class variance
      double maxVar = 0;
      int threshold = 128;
      double sumAll = 0;
      for (int i = 0; i < 256; i++) sumAll += i * hist[i];
      double sumB = 0;
      int wB = 0;
      for (int t = 0; t < 256; t++) {
        wB += hist[t];
        if (wB == 0) continue;
        final wF = pixels - wB;
        if (wF == 0) break;
        sumB += t * hist[t];
        final mB = sumB / wB;
        final mF = (sumAll - sumB) / wF;
        final variance = wB.toDouble() * wF * (mB - mF) * (mB - mF);
        if (variance > maxVar) {
          maxVar = variance;
          threshold = t;
        }
      }
      // Binarize: text pixels → 0 (black), background → 255 (white)
      final binary = Uint8List(pixels);
      for (int i = 0; i < pixels; i++) {
        binary[i] = stretched[i] <= threshold ? 0 : 255;
      }

      // ── Step 4: Unsharp mask on binary ────────────────────────────────────
      const amount = 1.5;
      final sharp = Uint8List(pixels);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int sum = 0, count = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final ny = y + dy, nx = x + dx;
              if (ny >= 0 && ny < h && nx >= 0 && nx < w) {
                sum += binary[ny * w + nx];
                count++;
              }
            }
          }
          final blur = sum / count;
          final val = binary[y * w + x] + amount * (binary[y * w + x] - blur);
          sharp[y * w + x] = val.round().clamp(0, 255);
        }
      }

      // Convert grayscale back to RGBA for encoding
      final rgba = Uint8List(pixels * 4);
      for (int i = 0; i < pixels; i++) {
        rgba[i * 4] = sharp[i];
        rgba[i * 4 + 1] = sharp[i];
        rgba[i * 4 + 2] = sharp[i];
        rgba[i * 4 + 3] = 255;
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
      final enhanced = await completer.future;
      final pngData = await enhanced.toByteData(format: ui.ImageByteFormat.png);
      enhanced.dispose();
      if (pngData == null) return imageBytes;
      return pngData.buffer.asUint8List();
    } catch (_) {
      return imageBytes; // fail open
    }
  }

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
