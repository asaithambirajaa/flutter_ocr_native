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
  Uint8List? _processedBytes;
  OcrResult? _result;
  DocumentDetails? _details;
  bool _loading = false;
  String? _error;
  DetectedDocType _docType = DetectedDocType.unknown;

  OcrWatermark get _watermark => const OcrWatermark(lines: {
        'Lead ID': 'LD-20250101-001',
        'Lat': '12.9716',
        'Long': '77.5946',
        'Agent': 'Ram Kumar',
        'Date': '2025-01-15 10:30',
      });

  Future<void> _pickFromCamera() async {
    final proceed = await OcrCaptureInstructions.showAsBottomSheet(context);
    if (proceed != true) return;
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) _processFile(File(picked.path));
  }

  Future<void> _pickFromGallery() async {
    if (isMobile) {
      final proceed = await OcrCaptureInstructions.showAsBottomSheet(context);
      if (proceed != true) return;
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) _processFile(File(picked.path));
    } else {
      _pickFromFileBrowser();
    }
  }

  Future<void> _pickFromFileBrowser() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'heic', 'tiff', 'pdf'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      _processFile(File(result.files.single.path!));
    }
  }

  bool _isPdf(File file) => file.path.toLowerCase().endsWith('.pdf');

  Future<void> _processFile(File file) async {
    final rawBytes = await file.readAsBytes();
    if (!mounted) return;

    Uint8List imageBytes;

    // Handle PDF: render first page to image
    if (_isPdf(file)) {
      final rendered = await OcrDocumentSaver.renderPdfPage(rawBytes);
      if (rendered == null) {
        setState(() => _error = 'Failed to render PDF. Platform may not support it.');
        return;
      }
      imageBytes = rendered;
    } else {
      imageBytes = rawBytes;
    }

    if (!mounted) return;

    // Auto-correct orientation
    final originalBytes = await OcrDocumentSaver.correctOrientation(imageBytes);
    if (!mounted) return;

    final croppedBytes = await OcrImageCropper.show(
      context,
      imageBytes: originalBytes,
      title: 'Crop Document',
    );

    if (croppedBytes == null) return;

    setState(() {
      _imageFile = file;
      _processedBytes = croppedBytes;
      _result = null;
      _details = null;
      _error = null;
      _loading = true;
      _docType = DetectedDocType.unknown;
    });

    try {
      final result = await _reader.readFromBytes(croppedBytes);

      // Use unified DocumentDetails — handles all doc types + face extraction
      final details = await DocumentDetails.fromResult(
        result,
        imageBytes: croppedBytes,
      );

      setState(() {
        _result = result;
        _details = details;
        _docType = details.docType;
      });

      if (mounted) _showValidationToast(details);
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

  void _showValidationToast(DocumentDetails details) {
    final String message;
    final Color bgColor;

    if (details.docType == DetectedDocType.unknown) {
      message = '⚠️ Document type not recognized';
      bgColor = Colors.orange;
    } else if (details.isValid) {
      message = '✅ Valid ${_docTypeLabel(details.docType)}';
      if (details.documentNumber != null) {
        bgColor = Colors.green;
      } else {
        bgColor = Colors.green;
      }
    } else if (details.documentNumber != null) {
      message = '❌ ${details.validationError}';
      bgColor = Colors.red;
    } else {
      message = '⚠️ No ${_docTypeLabel(details.docType)} number found';
      bgColor = Colors.orange;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _saveImage() async {
    if (_result == null || _processedBytes == null) return;
    final file = await OcrDocumentSaver.downloadBytes(
      imageBytes: _processedBytes!,
      watermark: _watermark,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    }
  }

  void _viewImage() {
    if (_result == null || _processedBytes == null) return;
    OcrDocumentViewer.show(
      context,
      result: _result!,
      originalBytes: _processedBytes!,
      title: _docTypeLabel(_docType),
      watermark: _watermark,
      onSave: (bytes) async {
        final file = await OcrDocumentSaver.downloadBytes(imageBytes: bytes);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
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
    final hasResult = _details != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Reader'),
        actions: [
          if (hasResult && !_loading)
            IconButton(
                onPressed: _viewImage, icon: const Icon(Icons.fullscreen)),
          if (hasResult && !_loading)
            IconButton(onPressed: _saveImage, icon: const Icon(Icons.download)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Action buttons
          _buildActionButtons(),
          const SizedBox(height: 16),

          // Image preview
          if (hasResult && _result!.hasAadhaar)
            GestureDetector(
              onTap: _viewImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_result!.maskedImageBytes!,
                    height: 250, width: double.infinity, fit: BoxFit.contain),
              ),
            )
          else if (_processedBytes != null)
            GestureDetector(
              onTap: hasResult ? _viewImage : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_processedBytes!,
                    height: 250, width: double.infinity, fit: BoxFit.contain),
              ),
            ),

          if (hasResult && !_loading) ...[
            const SizedBox(height: 12),
            if (_docType != DetectedDocType.unknown)
              Chip(
                avatar: Icon(_docTypeIcon(_docType), size: 18),
                label: Text('Detected: ${_docTypeLabel(_docType)}'),
                backgroundColor: Colors.indigo.shade50,
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _viewImage,
                      icon: const Icon(Icons.visibility),
                      label: const Text('View'))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: _saveImage,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Download'))),
            ]),
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
                          color:
                              Theme.of(context).colorScheme.onErrorContainer))),
            ),

          // Unified results display
          if (hasResult) ...[
            // Face photo
            if (_details!.hasPhoto) _buildPhotoCard(),
            if (_details!.hasPhoto) const SizedBox(height: 12),
            // Details card
            _buildDetailsCard(),
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
                          _result!.text.isEmpty
                              ? 'No text found'
                              : _result!.text,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_details!.photoBytes!,
                  width: 80, height: 100, fit: BoxFit.cover),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Photo Extracted',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Face detected from ${_docTypeLabel(_docType)} document',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    final fields = _details!.toDisplayMap(maskAadhaar: true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_docTypeLabel(_docType)} Details',
              style: Theme.of(context).textTheme.titleMedium),
          const Divider(),
          if (fields.isEmpty)
            const Text('No details detected')
          else
            ...fields.entries.map((e) => _detailRow(e.key, e.value)),
        ]),
      ),
    );
  }

  Widget _buildValidationCard() {
    final details = _details!;
    if (details.isValid) {
      final label = details.documentNumber != null
          ? '${_docTypeLabel(_docType)} Valid: ${details.documentNumber}'
          : '${_docTypeLabel(_docType)} Valid';
      return _validationChip(label, true);
    }
    if (details.documentNumber != null && details.validationError != null) {
      return _validationChip(details.validationError!, false);
    }
    return _validationChip(
        details.validationError ?? 'No document number found', false);
  }

  Widget _validationChip(String text, bool valid) {
    return Card(
      color: valid ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(valid ? Icons.check_circle : Icons.cancel,
              color: valid ? Colors.green : Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13))),
        const Text(': '),
        Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _buildActionButtons() {
    if (isMobile) {
      return Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: _loading ? null : _pickFromCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'))),
        const SizedBox(width: 12),
        Expanded(
            child: FilledButton.tonalIcon(
                onPressed: _loading ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'))),
      ]);
    }
    return Row(children: [
      Expanded(
          child: FilledButton.icon(
              onPressed: _loading ? null : _pickFromFileBrowser,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Image File'))),
      if (_imageFile != null) ...[
        const SizedBox(width: 12),
        Text(_imageFile!.path.split(Platform.pathSeparator).last,
            style: Theme.of(context).textTheme.bodySmall)
      ],
    ]);
  }

  String _docTypeLabel(DetectedDocType type) =>
      DocumentTypeDetector.label(type);

  IconData _docTypeIcon(DetectedDocType type) =>
      DocumentTypeDetector.icon(type);
}
