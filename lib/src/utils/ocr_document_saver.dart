import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ocr_result.dart';
import '../models/ocr_watermark.dart';

class OcrDocumentSaver {
  static const _channel = MethodChannel('com.flutter_ocr_native/text_recognition');

  /// Downloads to the platform's download folder.
  /// Burns [watermark] into the image if provided.
  static Future<File> download({
    required OcrResult result,
    required Uint8List originalImageBytes,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final dir = await _getDownloadDirectory();
    final imageBytes = result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    return _saveWithWatermark(imageBytes, dir, fileName, watermark);
  }

  /// Downloads from a file path.
  static Future<File> downloadFromPath({
    required OcrResult result,
    required String originalImagePath,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final originalBytes = await File(originalImagePath).readAsBytes();
    return download(
      result: result,
      originalImageBytes: originalBytes,
      fileName: fileName,
      watermark: watermark,
    );
  }

  /// Saves raw bytes to the platform's download folder.
  static Future<File> downloadBytes({
    required Uint8List imageBytes,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final dir = await _getDownloadDirectory();
    return _saveWithWatermark(imageBytes, dir, fileName, watermark);
  }

  /// Saves to a specific [directory].
  static Future<File> save({
    required OcrResult result,
    required Uint8List originalImageBytes,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final imageBytes = result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    return _saveWithWatermark(imageBytes, directory, fileName, watermark);
  }

  /// Saves from a file path to a specific [directory].
  static Future<File> saveFromPath({
    required OcrResult result,
    required String originalImagePath,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final originalBytes = await File(originalImagePath).readAsBytes();
    return save(
      result: result,
      originalImageBytes: originalBytes,
      directory: directory,
      fileName: fileName,
      watermark: watermark,
    );
  }

  /// Burns watermark into image bytes using native platform rendering.
  static Future<Uint8List> burnWatermark(
    Uint8List imageBytes,
    OcrWatermark watermark,
  ) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'burnWatermark',
      {
        'imageBytes': imageBytes,
        'lines': watermark.lines,
        'fontSize': watermark.fontSize * 2, // scale up for image resolution
        'textColor': watermark.textColor.toARGB32(),
        'bgColor': watermark.backgroundColor.toARGB32(),
        'padH': watermark.padding.left * 2,
        'padV': watermark.padding.top * 2,
      },
    );
    return result ?? imageBytes;
  }

  static Future<File> _saveWithWatermark(
    Uint8List imageBytes,
    Directory directory,
    String? fileName,
    OcrWatermark? watermark,
  ) async {
    final finalBytes = watermark != null
        ? await burnWatermark(imageBytes, watermark)
        : imageBytes;
    final name = fileName ?? 'ocr_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${directory.path}/$name');
    return file.writeAsBytes(finalBytes);
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
