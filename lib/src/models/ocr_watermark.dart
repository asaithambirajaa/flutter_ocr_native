import 'package:flutter/material.dart';

/// Configurable watermark to display below the document image.
///
/// Pass a list of key-value pairs that will be rendered as watermark text.
/// Example:
/// ```dart
/// OcrWatermark(
///   lines: {
///     'Lead ID': 'LD-20250101-001',
///     'Lat': '12.9716',
///     'Long': '77.5946',
///     'Agent': 'Ram Kumar',
///     'Date': '2025-01-15 10:30',
///   },
/// )
/// ```
class OcrWatermark {
  /// Key-value pairs to display as watermark lines.
  final Map<String, String> lines;

  /// Text color. Defaults to white with 80% opacity.
  final Color textColor;

  /// Background color behind the watermark. Defaults to black with 70% opacity.
  final Color backgroundColor;

  /// Font size for the viewer widget. Defaults to 12.
  /// For the downloaded image, font size is auto-scaled to the image resolution.
  final double fontSize;

  /// Padding inside the watermark area.
  final EdgeInsets padding;

  const OcrWatermark({
    required this.lines,
    this.textColor = const Color(0xCCFFFFFF),
    this.backgroundColor = const Color(0xB3000000),
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  /// Creates a copy with optional new values.
  OcrWatermark copyWith({
    Map<String, String>? lines,
    Color? textColor,
    Color? backgroundColor,
    double? fontSize,
    EdgeInsets? padding,
  }) {
    return OcrWatermark(
      lines: lines ?? this.lines,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
      padding: padding ?? this.padding,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OcrWatermark &&
          runtimeType == other.runtimeType &&
          lines == other.lines &&
          textColor == other.textColor &&
          backgroundColor == other.backgroundColor &&
          fontSize == other.fontSize &&
          padding == other.padding;

  @override
  int get hashCode => Object.hash(
        lines,
        textColor,
        backgroundColor,
        fontSize,
        padding,
      );
}
