import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A full-screen image cropper widget with rotate support.
/// Returns cropped image bytes when user confirms.
class OcrImageCropper extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;
  final double? aspectRatio;

  const OcrImageCropper({
    super.key,
    required this.imageBytes,
    this.title = 'Crop Image',
    this.aspectRatio,
  });

  /// Shows the cropper as a full-screen page.
  /// Returns cropped image bytes, or null if cancelled.
  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String title = 'Crop Image',
    double? aspectRatio,
  }) {
    return Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(
        builder: (_) => OcrImageCropper(
          imageBytes: imageBytes,
          title: title,
          aspectRatio: aspectRatio,
        ),
      ),
    );
  }

  @override
  State<OcrImageCropper> createState() => _OcrImageCropperState();
}

class _OcrImageCropperState extends State<OcrImageCropper> {
  late Uint8List _currentBytes;
  Rect _cropRect = Rect.zero;
  Size _imageSize = Size.zero;
  Size _displaySize = Size.zero;
  Offset _imageOffset = Offset.zero;
  bool _initialized = false;
  bool _processing = false;
  int _rotation = 0;

  _DragHandle? _activeHandle;
  Offset _dragStart = Offset.zero;
  Rect _dragStartRect = Rect.zero;

  static const _channel = MethodChannel('com.flutter_ocr_native/text_recognition');

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.imageBytes;
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final codec = await ui.instantiateImageCodec(_currentBytes);
    final frame = await codec.getNextFrame();
    _imageSize = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    codec.dispose();
    if (mounted) setState(() {});
  }

  void _calculateLayout(BoxConstraints constraints) {
    if (_imageSize == Size.zero) return;
    if (_initialized) return;

    final available = Size(constraints.maxWidth, constraints.maxHeight);
    final scale = min(available.width / _imageSize.width, available.height / _imageSize.height);
    _displaySize = Size(_imageSize.width * scale, _imageSize.height * scale);
    _imageOffset = Offset(
      (available.width - _displaySize.width) / 2,
      (available.height - _displaySize.height) / 2,
    );

    final margin = min(_displaySize.width, _displaySize.height) * 0.1;
    double cropW = _displaySize.width - margin * 2;
    double cropH = _displaySize.height - margin * 2;

    if (widget.aspectRatio != null) {
      if (cropW / cropH > widget.aspectRatio!) {
        cropW = cropH * widget.aspectRatio!;
      } else {
        cropH = cropW / widget.aspectRatio!;
      }
    }

    _cropRect = Rect.fromCenter(
      center: Offset(_imageOffset.dx + _displaySize.width / 2, _imageOffset.dy + _displaySize.height / 2),
      width: cropW,
      height: cropH,
    );
    _initialized = true;
  }

  Future<void> _rotateImage() async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      final result = await _channel.invokeMethod<Uint8List>('rotateImage', {
        'imageBytes': _currentBytes,
        'degrees': 90,
      });

      if (mounted && result != null) {
        _rotation = (_rotation + 90) % 360;
        _currentBytes = result;
        _initialized = false;
        _imageSize = Size.zero;
        _displaySize = Size.zero;
        _imageOffset = Offset.zero;
        _cropRect = Rect.zero;
        await _loadImageSize();
      }
    } catch (_) {}

    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _processing ? null : _rotateImage,
            icon: const Icon(Icons.rotate_right),
            tooltip: 'Rotate 90°',
          ),
          if (_processing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              onPressed: _initialized ? _doCrop : null,
              icon: const Icon(Icons.check),
              tooltip: 'Crop',
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _calculateLayout(constraints);

          return GestureDetector(
            onPanStart: _initialized ? _onPanStart : null,
            onPanUpdate: _initialized ? _onPanUpdate : null,
            onPanEnd: (_) => _activeHandle = null,
            child: Stack(
              children: [
                Center(
                  child: Image.memory(_currentBytes, fit: BoxFit.contain, key: ValueKey(_rotation)),
                ),
                if (_initialized) ...[
                  _buildOverlay(),
                  _buildHandles(),
                ],
                if (!_initialized)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlay() {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _CropOverlayPainter(_cropRect),
      ),
    );
  }

  Widget _buildHandles() {
    const size = 28.0;
    final corners = [
      Offset(_cropRect.left, _cropRect.top),
      Offset(_cropRect.right, _cropRect.top),
      Offset(_cropRect.left, _cropRect.bottom),
      Offset(_cropRect.right, _cropRect.bottom),
    ];

    return Stack(
      children: [
        // Crop border
        Positioned(
          left: _cropRect.left,
          top: _cropRect.top,
          child: IgnorePointer(
            child: Container(
              width: _cropRect.width,
              height: _cropRect.height,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
        // Grid lines
        Positioned(
          left: _cropRect.left,
          top: _cropRect.top,
          child: IgnorePointer(
            child: SizedBox(
              width: _cropRect.width,
              height: _cropRect.height,
              child: CustomPaint(painter: _GridPainter()),
            ),
          ),
        ),
        // Corner handles
        for (final corner in corners)
          Positioned(
            left: corner.dx - size / 2,
            top: corner.dy - size / 2,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.indigo, width: 2),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    const threshold = 35.0;

    final corners = [
      (Offset(_cropRect.left, _cropRect.top), _DragHandle.topLeft),
      (Offset(_cropRect.right, _cropRect.top), _DragHandle.topRight),
      (Offset(_cropRect.left, _cropRect.bottom), _DragHandle.bottomLeft),
      (Offset(_cropRect.right, _cropRect.bottom), _DragHandle.bottomRight),
    ];

    for (final (offset, handle) in corners) {
      if ((pos - offset).distance < threshold) {
        _activeHandle = handle;
        _dragStart = pos;
        _dragStartRect = _cropRect;
        return;
      }
    }

    if (_cropRect.contains(pos)) {
      _activeHandle = _DragHandle.move;
      _dragStart = pos;
      _dragStartRect = _cropRect;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == null) return;
    final delta = details.localPosition - _dragStart;

    setState(() {
      switch (_activeHandle!) {
        case _DragHandle.topLeft:
          _cropRect = Rect.fromLTRB(_dragStartRect.left + delta.dx, _dragStartRect.top + delta.dy, _dragStartRect.right, _dragStartRect.bottom);
        case _DragHandle.topRight:
          _cropRect = Rect.fromLTRB(_dragStartRect.left, _dragStartRect.top + delta.dy, _dragStartRect.right + delta.dx, _dragStartRect.bottom);
        case _DragHandle.bottomLeft:
          _cropRect = Rect.fromLTRB(_dragStartRect.left + delta.dx, _dragStartRect.top, _dragStartRect.right, _dragStartRect.bottom + delta.dy);
        case _DragHandle.bottomRight:
          _cropRect = Rect.fromLTRB(_dragStartRect.left, _dragStartRect.top, _dragStartRect.right + delta.dx, _dragStartRect.bottom + delta.dy);
        case _DragHandle.move:
          _cropRect = _dragStartRect.shift(delta);
      }

      // Clamp
      _cropRect = Rect.fromLTRB(
        _cropRect.left.clamp(_imageOffset.dx, _imageOffset.dx + _displaySize.width),
        _cropRect.top.clamp(_imageOffset.dy, _imageOffset.dy + _displaySize.height),
        _cropRect.right.clamp(_imageOffset.dx, _imageOffset.dx + _displaySize.width),
        _cropRect.bottom.clamp(_imageOffset.dy, _imageOffset.dy + _displaySize.height),
      );
      if (_cropRect.width < 50) _cropRect = Rect.fromLTWH(_cropRect.left, _cropRect.top, 50, _cropRect.height);
      if (_cropRect.height < 50) _cropRect = Rect.fromLTWH(_cropRect.left, _cropRect.top, _cropRect.width, 50);
    });
  }

  Future<void> _doCrop() async {
    setState(() => _processing = true);

    final scaleX = _imageSize.width / _displaySize.width;
    final scaleY = _imageSize.height / _displaySize.height;

    final cropX = ((_cropRect.left - _imageOffset.dx) * scaleX).round();
    final cropY = ((_cropRect.top - _imageOffset.dy) * scaleY).round();
    final cropW = (_cropRect.width * scaleX).round();
    final cropH = (_cropRect.height * scaleY).round();

    try {
      final result = await _channel.invokeMethod<Uint8List>('cropImage', {
        'imageBytes': _currentBytes,
        'x': cropX,
        'y': cropY,
        'width': cropW,
        'height': cropH,
      });

      if (mounted && result != null) {
        Navigator.pop(context, result);
      } else {
        setState(() => _processing = false);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context, _currentBytes);
    }
  }
}

enum _DragHandle { topLeft, topRight, bottomLeft, bottomRight, move }

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  _CropOverlayPainter(this.cropRect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRect(cropRect),
      ),
      Paint()..color = Colors.black.withAlpha(150),
    );
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter old) => old.cropRect != cropRect;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(80)
      ..strokeWidth = 0.5;

    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
