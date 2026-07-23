import 'package:flutter/material.dart';

import '../models/document_details.dart';
import '../models/ocr_result.dart';
import '../validators/document_type_detector.dart';

/// A card widget that displays parsed document details in a structured format.
/// Supports all document types: Aadhaar, PAN, Passport, DL, Voter ID, Cheque.
class OcrDetailsCard extends StatelessWidget {
  /// The OCR result to parse and display.
  final OcrResult result;

  /// Optional title for the card. Defaults to the detected document type label.
  final String? title;

  /// Whether to show the Aadhaar number masked. Defaults to true.
  final bool maskAadhaar;

  /// Whether to show all fields or only primary (Name, Address, Document No.).
  final bool showAllFields;

  /// Whether to show the masked image thumbnail. Defaults to true.
  final bool showMaskedImage;

  const OcrDetailsCard({
    super.key,
    required this.result,
    this.title,
    this.maskAadhaar = true,
    this.showAllFields = true,
    this.showMaskedImage = true,
  });

  @override
  Widget build(BuildContext context) {
    final details = DocumentDetails.fromResultSync(result);
    final fields = details.toDisplayMap(maskAadhaar: maskAadhaar);
    final cardTitle =
        title ?? DocumentTypeDetector.label(details.docType);

    if (fields.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No details found',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }

    final displayFields = showAllFields
        ? fields
        : Map.fromEntries(
            fields.entries.take(3),
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with masked image thumbnail
            Row(
              children: [
                Expanded(
                  child: Text(cardTitle,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (showMaskedImage && result.hasAadhaar)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(result.maskedImageBytes!,
                        width: 48, height: 32, fit: BoxFit.cover),
                  ),
              ],
            ),
            const Divider(),
            ...displayFields.entries.map((entry) {
              String value = entry.value;
              // Mask if not already masked and masking is enabled
              if (maskAadhaar &&
                  entry.key == 'Aadhaar No.' &&
                  !value.contains('XXXX')) {
                value = _maskNumber(value);
              }
              return _buildRow(context, entry.key, value);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _maskNumber(String number) {
    final pattern =
        RegExp(r'(?<!\d)(\d{4})([\s\-]+)(\d{4})([\s\-]+)(\d{4})(?!\d)');
    final match = pattern.firstMatch(number);
    if (match != null) {
      return 'XXXX${match.group(2)}XXXX${match.group(4)}${match.group(5)}';
    }
    final digits = number.replaceAll(RegExp(r'[^\dX]'), '');
    if (digits.length >= 4) {
      final last4 = number.substring(number.length - 4);
      return 'XXXX XXXX $last4';
    }
    return number;
  }
}
