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
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
  }
}
