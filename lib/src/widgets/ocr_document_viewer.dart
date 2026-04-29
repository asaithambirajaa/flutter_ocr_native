import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../models/ocr_watermark.dart';
import '../utils/ocr_document_saver.dart';

/// Full-screen document viewer with pinch-to-zoom and optional watermark.
class OcrDocumentViewer extends StatelessWidget {
  final OcrResult result;
  final File? originalFile;
  final Uint8List? originalBytes;
  final String title;
  final Color backgroundColor;
  final Future<void> Function(Uint8List imageBytes)? onSave;
  final double minScale;
  final double maxScale;
  final OcrWatermark? watermark;

  const OcrDocumentViewer({
    super.key,
    required this.result,
    this.originalFile,
    this.originalBytes,
    this.title = 'Document',
    this.backgroundColor = Colors.black,
    this.onSave,
    this.minScale = 0.5,
    this.maxScale = 5.0,
    this.watermark,
  });

  static Future<void> show(
    BuildContext context, {
    required OcrResult result,
    File? originalFile,
    Uint8List? originalBytes,
    String title = 'Document',
    Future<void> Function(Uint8List imageBytes)? onSave,
    OcrWatermark? watermark,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrDocumentViewer(
          result: result,
          originalFile: originalFile,
          originalBytes: originalBytes,
          title: title,
          onSave: onSave,
          watermark: watermark,
        ),
      ),
    );
  }

  Future<Uint8List?> _getRawImageBytes() async {
    if (result.hasAadhaar) return result.maskedImageBytes;
    if (originalBytes != null) return originalBytes;
    if (originalFile != null) return originalFile!.readAsBytes();
    return null;
  }

  Future<Uint8List?> _getImageBytesWithWatermark() async {
    final bytes = await _getRawImageBytes();
    if (bytes == null) return null;
    if (watermark != null) {
      return OcrDocumentSaver.burnWatermark(bytes, watermark!);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        actions: [
          if (onSave != null)
            IconButton(
              onPressed: () async {
                final bytes = await _getImageBytesWithWatermark();
                if (bytes != null) await onSave!(bytes);
              },
              icon: const Icon(Icons.save_alt),
              tooltip: 'Save',
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: minScale,
          maxScale: maxScale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildImage(),
              if (watermark != null) _buildWatermark(watermark!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (result.hasAadhaar) {
      return Image.memory(result.maskedImageBytes!, fit: BoxFit.contain);
    }
    if (originalBytes != null) {
      return Image.memory(originalBytes!, fit: BoxFit.contain);
    }
    if (originalFile != null) {
      return Image.file(originalFile!, fit: BoxFit.contain);
    }
    return const Center(
      child: Text('No image available', style: TextStyle(color: Colors.white)),
    );
  }

  Widget _buildWatermark(OcrWatermark wm) {
    return Container(
      width: double.infinity,
      color: wm.backgroundColor,
      padding: wm.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: wm.lines.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '${e.key}: ${e.value}',
              style: TextStyle(color: wm.textColor, fontSize: wm.fontSize),
            ),
          );
        }).toList(),
      ),
    );
  }
}
