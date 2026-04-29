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
    }
    return getApplicationDocumentsDirectory();
  }
}
