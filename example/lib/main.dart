import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';
import 'package:image_picker/image_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deviceSecurity = await OcrIntegrity.checkDeviceSecurity();
  runApp(OcrExampleApp(deviceCompromised: !deviceSecurity.secure));
}

bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class OcrExampleApp extends StatelessWidget {
  final bool deviceCompromised;
  const OcrExampleApp({super.key, this.deviceCompromised = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OCR Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: deviceCompromised
          ? const _CompromisedDeviceScreen()
          : const OcrHomePage(),
    );
  }
}

/// Full-screen block shown when device is rooted/jailbroken.
/// The app cannot be used until the device is secured.
class _CompromisedDeviceScreen extends StatelessWidget {
  const _CompromisedDeviceScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.gpp_bad, size: 80, color: Colors.white),
                const SizedBox(height: 24),
                const Text(
                  'Device Security Risk',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This device appears to be rooted or jailbroken.\n\n'
                  'For the security of your documents and personal data, '
                  'this application cannot be used on compromised devices.\n\n'
                  'Please use a secure, unmodified device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white70, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.exit_to_app, color: Colors.white),
                  label: const Text('Exit App',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
  OcrAuditRecord? _auditRecord;
  List<String> _consistencyErrors = [];
  bool _loading = false;
  bool _sessionLocked = false;
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
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'bmp',
        'gif',
        'heic',
        'tiff',
        'pdf'
      ],
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
        setState(() =>
            _error = 'Failed to render PDF. Platform may not support it.');
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

    // ── Gap 3: Image quality gate ─────────────────────────────────────────
    // Quality check: warn only — OcrReader auto-enhances + retries internally.
    final qualityError = OcrIntegrity.checkImageQuality(croppedBytes);
    if (qualityError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text(
            '⚠️ Low quality image — attempting OCR with enhancement…'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ));
    }
    final Uint8List ocrBytes = croppedBytes;

    setState(() {
      _imageFile = file;
      _processedBytes = ocrBytes;
      _result = null;
      _details = null;
      _auditRecord = null;
      _consistencyErrors = [];
      _error = null;
      _loading = true;
      _docType = DetectedDocType.unknown;
    });

    try {
      // OcrReader._processWithFallback already enhanced + retried internally.
      final ocrResult = await _reader.readFromBytes(ocrBytes);

      List<double> confidencesOf(OcrResult r) => r.blocks
          .expand((b) => b.lines)
          .map((l) => l.confidence ?? 0.0)
          .toList();
      // Confidence warning only — never block
      final confidenceWarning = OcrIntegrity.checkConfidence(
        confidencesOf(ocrResult),
        threshold: OcrIntegrity.minConfidenceAfterEnhance,
      );

      // Use unified DocumentDetails — handles all doc types + face extraction
      final details = await DocumentDetails.fromResult(
        ocrResult,
        imageBytes: ocrBytes,
      );

      // ── Gap 1 & 6: Create audit record with unique scanId ─────────────────
      final auditRecord = OcrAuditRecord.create(
        details,
        ocrBytes,
        // agentId: 'Raja',
        sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
      );

      // ── Gap 4: Consistency + expiry checks ────────────────────────────────
      final consistencyErrors = [
        ...OcrIntegrity.consistencyErrors(details),
        if (confidenceWarning != null) confidenceWarning,
      ];

      // ── Gap 5: Persist audit record ───────────────────────────────────────
      await OcrIntegrity.persistAuditRecord(auditRecord);

      setState(() {
        _result = ocrResult;
        _details = details;
        _docType = details.docType;
        _auditRecord = auditRecord;
        _consistencyErrors = consistencyErrors;
      });

      if (mounted) _showValidationToast(details);
    } on EmptyImageException {
      setState(() => _error = 'No text detected in the image');
    } on HandwrittenTextException {
      setState(() => _error =
          'Handwritten text detected. Only printed documents are accepted');
    } on LowQualityImageException catch (e) {
      setState(() => _error = e.message);
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
    if (_result == null || _processedBytes == null || _auditRecord == null)
      return;

    // ── Re-verify before save ───────────────────────────────────────────────
    final verification =
        OcrIntegrity.verify(_details!, _processedBytes!, _auditRecord!);
    if (!verification.passed) {
      await _handleTamper(verification);
      return;
    }

    final file = await OcrDocumentSaver.downloadBytes(
      imageBytes: _processedBytes!,
      watermark: _watermark,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
    }
  }

  /// Full tamper response:
  /// 1. Log tamper event to disk
  /// 2. Wipe all sensitive state from memory
  /// 3. Lock the session (no further actions allowed)
  /// 4. Show a blocking, non-dismissible alert dialog
  Future<void> _handleTamper(OcrVerificationResult verification) async {
    // 1. Log
    final event = TamperEvent.fromVerification(verification, _auditRecord!);
    await OcrIntegrity.persistTamperEvent(event);
    // TODO(production): POST event.toJson() to your security endpoint here

    // 2. Wipe sensitive state
    setState(() {
      _processedBytes = null;
      _result = null;
      _details = null;
      _auditRecord = null;
      _consistencyErrors = [];
      _imageFile = null;
      _sessionLocked = true;
    });

    // 3 & 4. Show blocking dialog — user must acknowledge, cannot dismiss
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.gpp_bad, color: Colors.red, size: 48),
        title: const Text('Security Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              verification.reason,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'All captured data has been cleared.\n'
              'This incident has been logged.\n\n'
              'Please restart the scan with the original document.',
            ),
            const SizedBox(height: 12),
            Text(
              'Scan ID: ${event.scanId}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
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
          if (hasResult && !_loading && !_sessionLocked)
            IconButton(
                onPressed: _viewImage, icon: const Icon(Icons.fullscreen)),
          if (hasResult && !_loading && !_sessionLocked)
            IconButton(onPressed: _saveImage, icon: const Icon(Icons.download)),
        ],
      ),
      body: _sessionLocked
          ? _buildLockedScreen()
          : ListView(
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
                          height: 250,
                          width: double.infinity,
                          fit: BoxFit.contain),
                    ),
                  )
                else if (_processedBytes != null)
                  GestureDetector(
                    onTap: hasResult ? _viewImage : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_processedBytes!,
                          height: 250,
                          width: double.infinity,
                          fit: BoxFit.contain),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer))),
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
                  // Integrity card
                  _buildIntegrityCard(),
                  const SizedBox(height: 12),
                  // Raw text
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: Text('Raw OCR Text',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium)),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  tooltip: 'Copy raw text',
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _result!.text));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Raw OCR text copied!'),
                                          duration: Duration(seconds: 2)),
                                    );
                                  },
                                ),
                              ],
                            ),
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

  Widget _buildLockedScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Session Locked',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.red)),
            const SizedBox(height: 8),
            const Text(
              'A tamper attempt was detected and logged.\n'
              'Start a new scan to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => setState(() {
                _sessionLocked = false;
                _error = null;
                _docType = DetectedDocType.unknown;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Start New Scan'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
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
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                'Tap any field to edit — triggers tamper detection on download',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
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
    if (kDebugMode && _details != null) {
      return _EditableDetailRow(
        label: label,
        value: value,
        onChanged: (newValue) {
          setState(() {
            _details = _details!.copyWithField(label, newValue);
          });
        },
      );
    }
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

  Widget _buildIntegrityCard() {
    final record = _auditRecord;
    if (record == null) return const SizedBox.shrink();

    final hasConsistencyIssues = _consistencyErrors.isNotEmpty;

    return Card(
      color: hasConsistencyIssues ? Colors.orange.shade50 : Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                hasConsistencyIssues
                    ? Icons.warning_amber
                    : Icons.verified_user,
                color: hasConsistencyIssues ? Colors.orange : Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                hasConsistencyIssues
                    ? 'Integrity: Warnings'
                    : 'Integrity: Verified',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ]),
            const Divider(),
            _detailRow('Scan ID', record.scanId),
            _detailRow('Data Hash', '${record.dataHash.substring(0, 16)}…'),
            _detailRow('Image Hash', '${record.imageHash.substring(0, 16)}…'),
            _detailRow('Captured At', record.capturedAt.toLocal().toString()),
            if (record.agentId != null) _detailRow('Agent', record.agentId!),
            if (hasConsistencyIssues) ...[
              const SizedBox(height: 8),
              Text('Consistency Issues:',
                  style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              ..._consistencyErrors.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $e',
                      style: TextStyle(
                          color: Colors.orange.shade900, fontSize: 13)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (isMobile) {
      return Column(children: [
        Row(children: [
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
        ]),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const _GenericOcrPage())),
          icon: const Icon(Icons.text_fields),
          label: const Text('Generic Label-Value OCR'),
        ),
      ]);
    }
    return Column(children: [
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: _loading ? null : _pickFromFileBrowser,
                icon: const Icon(Icons.folder_open),
                label: const Text('Open Image / PDF'))),
        if (_imageFile != null) ...[
          const SizedBox(width: 12),
          Text(_imageFile!.path.split(Platform.pathSeparator).last,
              style: Theme.of(context).textTheme.bodySmall)
        ],
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const _GenericOcrPage())),
          icon: const Icon(Icons.text_fields),
          label: const Text('Generic Label-Value OCR'),
        ),
      ),
    ]);
  }

  String _docTypeLabel(DetectedDocType type) =>
      DocumentTypeDetector.label(type);

  IconData _docTypeIcon(DetectedDocType type) =>
      DocumentTypeDetector.icon(type);
}

/// Editable detail row — debug only.
/// Tapping the value opens an inline text field.
/// Any edit mutates _details via copyWithField, breaking the data hash.
class _EditableDetailRow extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _EditableDetailRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_EditableDetailRow> createState() => _EditableDetailRowState();
}

class _EditableDetailRowState extends State<_EditableDetailRow> {
  bool _editing = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_EditableDetailRow old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 120,
          child: Text(widget.label,
              style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
        const Text(': '),
        Expanded(
          child: _editing
              ? TextField(
                  controller: _ctrl,
                  autofocus: true,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Colors.deepOrange),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    setState(() => _editing = false);
                    if (v != widget.value) widget.onChanged(v);
                  },
                  onTapOutside: (_) {
                    setState(() => _editing = false);
                    if (_ctrl.text != widget.value) {
                      widget.onChanged(_ctrl.text);
                    }
                  },
                )
              : GestureDetector(
                  onTap: () => setState(() => _editing = true),
                  child: Row(children: [
                    Expanded(
                      child: Text(widget.value,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ),
                    Icon(Icons.edit, size: 13, color: Colors.grey.shade400),
                  ]),
                ),
        ),
      ]),
    );
  }
}

// ── Generic Label-Value OCR Page ─────────────────────────────────────────────

/// Uploads any PDF or image, runs OCR, parses every `Label: Value` /
/// `Label - Value` / `Label = Value` line, and shows them as editable fields.
class _GenericOcrPage extends StatefulWidget {
  const _GenericOcrPage();

  @override
  State<_GenericOcrPage> createState() => _GenericOcrPageState();
}

class _GenericOcrPageState extends State<_GenericOcrPage> {
  final _reader = OcrReader(validateDocument: false);
  bool _loading = false;
  String? _error;
  String _rawText = '';

  /// Parsed label → TextEditingController
  final Map<String, TextEditingController> _fields = {};

  /// Lines that had no separator — shown as plain text below the fields
  final List<String> _unparsed = [];

  @override
  void dispose() {
    for (final c in _fields.values) c.dispose();
    _reader.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'pdf'],
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    _process(File(result.files.single.path!));
  }

  Future<void> _pickMobile(ImageSource src) async {
    final picked = await ImagePicker().pickImage(source: src);
    if (picked != null) _process(File(picked.path));
  }

  Future<void> _process(File file) async {
    setState(() {
      _loading = true;
      _error = null;
      _rawText = '';
      for (final c in _fields.values) {
        c.dispose();
      }
      _fields.clear();
      _unparsed.clear();
    });

    try {
      final rawBytes = await file.readAsBytes();
      final Uint8List imageBytes;

      if (file.path.toLowerCase().endsWith('.pdf')) {
        final rendered = await OcrDocumentSaver.renderPdfPage(rawBytes);
        if (rendered == null) throw Exception('PDF render failed');
        imageBytes = rendered;
      } else {
        imageBytes = rawBytes;
      }

      final corrected = await OcrDocumentSaver.correctOrientation(imageBytes);

      // Image quality + blur gate — enhance then re-check
      final qualityError = OcrIntegrity.checkImageQuality(corrected);
      if (qualityError != null) throw LowQualityImageException(qualityError);
      Uint8List ocrReady = corrected;
      if (await OcrIntegrity.checkBlurriness(corrected) != null) {
        ocrReady = await OcrDocumentSaver.enhanceForOcr(corrected);
        final stillBlurry = await OcrIntegrity.checkBlurriness(ocrReady);
        if (stillBlurry != null) throw LowQualityImageException(stillBlurry);
      }

      final ocrResult = await _reader.readFromBytes(ocrReady);
      final text = ocrResult.text;

      // Parse label-value pairs — separators: : - =
      final sep = RegExp(r'^(.{2,50}?)\s*[:\-=]\s*(.+)$');
      final newFields = <String, TextEditingController>{};
      final unparsed = <String>[];

      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final m = sep.firstMatch(t);
        if (m != null) {
          final label = m.group(1)!.trim();
          final value = m.group(2)!.trim();
          // Skip lines where the "label" part looks like a number or is too short
          if (label.length < 2 || RegExp(r'^\d+$').hasMatch(label)) {
            unparsed.add(t);
          } else {
            // Deduplicate: append index if label already exists
            var key = label;
            var idx = 2;
            while (newFields.containsKey(key)) key = '$label ($idx++)';
            newFields[key] = TextEditingController(text: value);
          }
        } else {
          unparsed.add(t);
        }
      }

      setState(() {
        _rawText = text;
        _fields.addAll(newFields);
        _unparsed.addAll(unparsed);
      });
    } on LowQualityImageException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generic Label-Value OCR')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pick buttons
          if (isMobile)
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _pickMobile(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton.tonalIcon(
                      onPressed: _loading
                          ? null
                          : () => _pickMobile(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'))),
            ])
          else
            FilledButton.icon(
              onPressed: _loading ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Image / PDF'),
            ),

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

          // Parsed fields
          if (_fields.isNotEmpty) ...[
            Text('Extracted Fields (${_fields.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    decoration: InputDecoration(
                      labelText: e.key,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                )),
          ],

          // Unparsed lines
          if (_unparsed.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text('Other lines (${_unparsed.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              children: _unparsed
                  .map((l) => ListTile(dense: true, title: Text(l)))
                  .toList(),
            ),
          ],

          // Raw OCR text
          if (_rawText.isNotEmpty) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              title: Text('Raw OCR Text',
                  style: Theme.of(context).textTheme.titleSmall),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(_rawText,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
