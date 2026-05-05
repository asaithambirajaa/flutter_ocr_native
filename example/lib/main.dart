import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const OcrExampleApp());

bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
      );

  // Mobile: pick from camera
  Future<void> _pickFromCamera() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) _processFile(File(picked.path));
  }

  // Mobile: pick from gallery
  Future<void> _pickFromGallery() async {
    if (isMobile) {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) _processFile(File(picked.path));
    } else {
      _pickFromFileBrowser();
    }
  }

  // Desktop: pick from file browser
  Future<void> _pickFromFileBrowser() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      _processFile(File(result.files.single.path!));
    }
  }

  Future<void> _processFile(File file) async {
    setState(() {
      _imageFile = file;
      _result = null;
      _error = null;
      _loading = true;
    });

    try {
      final result = await _reader.readFromPath(file.path);
      setState(() => _result = result);

      // Show validation toast
      if (mounted) _showValidationToast(result);
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

  void _showValidationToast(OcrResult result) {
    String message;
    Color bgColor;

    if (result.isAadhaarValid) {
      message = '✅ Valid Aadhaar number';
      bgColor = Colors.green;
    } else if (result.aadhaarError != null && result.hasAadhaar) {
      message = '❌ Aadhaar: ${result.aadhaarError}';
      bgColor = Colors.red;
    } else if (result.isPanValid) {
      message = '✅ Valid PAN — ${result.panHolderType}';
      bgColor = Colors.green;
    } else if (result.panError != null && result.panError != 'PAN number not found') {
      message = '❌ PAN: ${result.panError}';
      bgColor = Colors.red;
    } else {
      message = '⚠️ No Aadhaar or PAN number found in document';
      bgColor = Colors.orange;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor,
        duration: const Duration(seconds: 3),
      ),
    );
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
      appBar: AppBar(
        title: const Text('OCR Reader'),
        actions: [
          if (hasResult && !_loading)
            IconButton(
              onPressed: _viewImage,
              icon: const Icon(Icons.fullscreen),
              tooltip: 'View Full Screen',
            ),
          if (hasResult && !_loading)
            IconButton(
              onPressed: _saveImage,
              icon: const Icon(Icons.download),
              tooltip: 'Download',
            ),
        ],
      ),
      body: Row(
        children: [
          // Desktop: sidebar with file info
          if (isDesktop && hasResult)
            SizedBox(
              width: 300,
              child: _buildSidebar(),
            ),
          // Main content
          Expanded(child: _buildMainContent(hasResult)),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          OcrDetailsCard(result: _result!, maskAadhaar: true),
          const SizedBox(height: 12),
          _buildValidationCard(),
          const SizedBox(height: 12),
          Text('Raw Text', style: Theme.of(context).textTheme.titleSmall),
          const Divider(),
          SelectableText(
            _result!.text.isEmpty ? 'No text found' : _result!.text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildValidationCard() {
    if (_result == null) return const SizedBox.shrink();

    if (!_result!.isAadhaarValid && !_result!.isPanValid && !_result!.hasAadhaar) {
      return Card(
        color: Colors.orange.shade50,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('No Aadhaar or PAN number found in document')),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document Validation',
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            if (_result!.isAadhaarValid)
              _buildValidationRow('Aadhaar', 'Valid', true),
            if (!_result!.isAadhaarValid && _result!.hasAadhaar)
              _buildValidationRow('Aadhaar', _result!.aadhaarError ?? 'Invalid', false),
            if (_result!.isPanValid)
              _buildValidationRow('PAN', 'Valid — ${_result!.panHolderType}', true),
            if (!_result!.isPanValid && _result!.panError != null && _result!.panError != 'PAN number not found')
              _buildValidationRow('PAN', _result!.panError!, false),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationRow(String label, String status, bool isValid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.cancel,
            color: isValid ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(status)),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool hasResult) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Action buttons — adapt to platform
        _buildActionButtons(),
        const SizedBox(height: 16),

        // Image preview
        if (hasResult && _result!.hasAadhaar)
          GestureDetector(
            onTap: _viewImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_result!.maskedImageBytes!,
                  height: isDesktop ? 400 : 250,
                  width: double.infinity,
                  fit: BoxFit.contain),
            ),
          )
        else if (_imageFile != null)
          GestureDetector(
            onTap: hasResult ? _viewImage : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_imageFile!,
                  height: isDesktop ? 400 : 250,
                  width: double.infinity,
                  fit: BoxFit.contain),
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

        // On mobile, show text results below image
        if (!isDesktop && hasResult) ...[
          // Structured details card
          OcrDetailsCard(result: _result!, maskAadhaar: true),
          const SizedBox(height: 12),
          // Validation card
          _buildValidationCard(),
          const SizedBox(height: 12),
          // Raw text
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Raw Text',
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
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    if (isMobile) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _loading ? null : _pickFromCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Camera'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _loading ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('Gallery'),
            ),
          ),
        ],
      );
    }

    // Desktop
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _loading ? null : _pickFromFileBrowser,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Image File'),
          ),
        ),
        if (_imageFile != null) ...[
          const SizedBox(width: 12),
          Text(
            _imageFile!.path.split(Platform.pathSeparator).last,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
