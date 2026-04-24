import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';

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
  final _reader = OcrReader();
  final _picker = ImagePicker();

  File? _imageFile;
  OcrResult? _result;
  bool _loading = false;
  String? _error;

  Future<void> _pickAndRecognize(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _result = null;
      _error = null;
      _loading = true;
    });
    final reader = OcrReader(validateDocument: true, maskAadhaar: true);
    try {
      final result = await reader.readFromPath(picked.path);
      setState(() => _result = result);
    } /* catch (e) {
      setState(() => _error = e.toString());
    }  */ on EmptyImageException {
      setState(() => _error = "No text detected in the image");
    } on HandwrittenTextException {
      setState(
        () => _error =
            "Handwritten text detected. Only printed documents are accepted",
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Reader')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Action buttons
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

          // Image preview — show masked image if Aadhaar detected, else original
          if (_result != null && _result!.hasAadhaar)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_result!.maskedImageBytes!, height: 250, fit: BoxFit.cover),
            )
          else if (_imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_imageFile!, height: 250, fit: BoxFit.cover),
            ),

          const SizedBox(height: 16),

          // Loading
          if (_loading) const Center(child: CircularProgressIndicator()),

          // Error
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),

          // Results
          if (_result != null) ...[
            // Full text
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extracted Text',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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

            // Structured blocks
            Text(
              '${_result!.blocks.length} block(s) found',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ..._result!.blocks.asMap().entries.map((entry) {
              final i = entry.key;
              final block = entry.value;
              return Card(
                child: ExpansionTile(
                  title: Text('Block ${i + 1}'),
                  subtitle: Text(
                    block.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: block.lines.map((line) {
                    return ListTile(
                      dense: true,
                      title: Text(line.text),
                      subtitle: Text(
                        'Confidence: ${((line.confidence ?? 0) * 100).toStringAsFixed(1)}%  •  '
                        'Bounds: (${line.boundingBox.left.toInt()}, ${line.boundingBox.top.toInt()}, '
                        '${line.boundingBox.width.toInt()}×${line.boundingBox.height.toInt()})',
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
