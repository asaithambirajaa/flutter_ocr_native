import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../models/ocr_watermark.dart';

class OcrDocumentSaver {
  /// Saves the document image to [directory].
  /// If [watermark] is provided, burns watermark text into the image.
  /// Returns the saved [File].
  static Future<File> save({
    required OcrResult result,
    required Uint8List originalImageBytes,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
  }) async {
    final imageBytes = result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    final finalBytes = watermark != null
        ? await _burnWatermark(imageBytes, watermark)
        : imageBytes;

    final name = fileName ?? 'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${directory.path}/$name');
    return file.writeAsBytes(finalBytes);
  }

  /// Saves the document image from a file path.
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

  /// Burns watermark text onto the bottom of the image.
  static Future<Uint8List> _burnWatermark(Uint8List imageBytes, OcrWatermark watermark) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final lineHeight = watermark.fontSize + 4;
    final wmHeight = (watermark.lines.length * lineHeight) +
        watermark.padding.top + watermark.padding.bottom;
    final totalHeight = image.height + wmHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, image.width.toDouble(), totalHeight));

    // Draw original image
    canvas.drawImage(image, Offset.zero, Paint());

    // Draw watermark background
    final bgPaint = Paint()..color = watermark.backgroundColor;
    canvas.drawRect(
      Rect.fromLTWH(0, image.height.toDouble(), image.width.toDouble(), wmHeight),
      bgPaint,
    );

    // Draw watermark text
    var y = image.height.toDouble() + watermark.padding.top;
    for (final entry in watermark.lines.entries) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: TextAlign.left,
        fontSize: watermark.fontSize,
      ))
        ..pushStyle(ui.TextStyle(color: watermark.textColor))
        ..addText('${entry.key}: ${entry.value}');

      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: image.width.toDouble() - watermark.padding.left - watermark.padding.right));

      canvas.drawParagraph(paragraph, Offset(watermark.padding.left, y));
      y += lineHeight;
    }

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(image.width, totalHeight.toInt());
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

    image.dispose();
    finalImage.dispose();

    return byteData!.buffer.asUint8List();
  }
}
