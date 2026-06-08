import 'package:flutter/services.dart';

import 'models/ocr_result.dart';
import 'ocr_platform_interface.dart';

class OcrMethodChannel implements OcrPlatformInterface {
  static const _channel = MethodChannel('com.flutter_ocr_native/text_recognition');

  @override
  Future<OcrResult> recognizeFromPath(String imagePath) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'recognizeFromPath',
      {'imagePath': imagePath},
    );
    return OcrResult.fromMap(result ?? {});
  }

  @override
  Future<OcrResult> recognizeFromBytes(Uint8List bytes) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'recognizeFromBytes',
      {'bytes': bytes},
    );
    return OcrResult.fromMap(result ?? {});
  }

  @override
  Future<Uint8List?> renderPdfPage(Uint8List pdfBytes, {int page = 0, double scale = 2.0}) async {
    final result = await _channel.invokeMethod<Uint8List>(
      'renderPdfPage',
      {'pdfBytes': pdfBytes, 'page': page, 'scale': scale},
    );
    return result;
  }

  @override
  Future<int> getPdfPageCount(Uint8List pdfBytes) async {
    final result = await _channel.invokeMethod<int>(
      'getPdfPageCount',
      {'pdfBytes': pdfBytes},
    );
    return result ?? 0;
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
  }
}
