import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const OcrExampleApp());

class OcrExampleApp extends StatelessWidget {
  const OcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const OcrHomePage(),
    );
  }
}

class OcrHomePage extends StatefulWidget {
  const OcrHomePage({super.key});

  @override
  State<OcrHomePage> createState() => _OcrHomePageState();
}

class _OcrHomePageState extends State<OcrHomePage> {
  final _reader = OcrReader(validateDocument: true, maskAadhaar: true);
  final _picker = ImagePicker();

  File? _imageFile;
  OcrResult? _result;
  bool _loading = false;
  String? _error;

  OcrWatermark get _watermark => const OcrWatermark(
        lines: {
          'Lead ID': 'LD-20250101-001',
          'Lat': '12.9716',
          'Long': '77.5946',
          'Agent': 'Ram Kumar',
          'Date': '2025-01-15 10:30',
        },
        fontSize: 16,
      );

  Future<void> _pickAndRecognize(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _result = null;
      _error = null;
      _loading = true;
    });

    try {
      final result = await _reader.readFromPath(picked.path);
      setState(() => _result = result);
    } on EmptyImageException {
      setState(() => _error = 'No text detected in the image');
    } on HandwrittenTextException {
      setState(() => _error =
          'Handwritten text detected. Only printed documents are accepted');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveImage() async {
    if (_result == null || _imageFile == null) return;
    final file = await OcrDocumentSaver.downloadFromPath(
      result: _result!,
      originalImagePath: _imageFile!.path,
      watermark: _watermark,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    }
  }

  void _viewImage() {
    if (_result == null) return;
    OcrDocumentViewer.show(
      context,
      result: _result!,
      originalFile: _imageFile,
      title: _result!.hasAadhaar ? 'Masked Document' : 'Document',
      watermark: _watermark,
      onSave: (bytes) async {
        final file = await OcrDocumentSaver.downloadBytes(imageBytes: bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to ${file.path}')),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _result != null;

    return Scaffold(
      appBar: AppBar(title: const Text('OCR Reader')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _loading
                      ? null
                      : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasResult && _result!.hasAadhaar)
            GestureDetector(
              onTap: _viewImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_result!.maskedImageBytes!,
                    height: 250, width: double.infinity, fit: BoxFit.cover),
              ),
            )
          else if (_imageFile != null)
            GestureDetector(
              onTap: hasResult ? _viewImage : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_imageFile!,
                    height: 250, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          if (hasResult && !_loading) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _viewImage,
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveImage,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            ),
          if (hasResult) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Extracted Text',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Divider(),
                    SelectableText(
                      _result!.text.isEmpty ? 'No text found' : _result!.text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ..._result!.blocks.asMap().entries.map((entry) {
              final i = entry.key;
              final block = entry.value;
              return Card(
                child: ExpansionTile(
                  title: Text('Block ${i + 1}'),
                  subtitle: Text(block.text,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  children: block.lines.map((line) {
                    return ListTile(
                      dense: true,
                      title: Text(line.text),
                      subtitle: Text(
                        'Confidence: ${((line.confidence ?? 0) * 100).toStringAsFixed(1)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
