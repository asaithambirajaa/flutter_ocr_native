import 'package:flutter/material.dart';

import '../models/ocr_result.dart';
import '../models/voter_id_details.dart';

/// A card widget that displays parsed Voter ID (EPIC) details in a structured format.
/// Shows EPIC No., Name, and Address as primary fields.
class VoterIdDetailsCard extends StatelessWidget {
  /// The OCR result to parse and display.
  final OcrResult result;

  /// Optional title for the card. Defaults to "Voter ID Details".
  final String title;

  /// Whether to show all fields or only primary (EPIC No., Name, Address).
  final bool showAllFields;

  const VoterIdDetailsCard({
    super.key,
    required this.result,
    this.title = 'Voter ID Details',
    this.showAllFields = false,
  });

  @override
  Widget build(BuildContext context) {
    final voter = VoterIdDetails.fromText(result.text);
    final fields =
        showAllFields ? voter.toDisplayMap() : voter.toPrimaryFieldsMap();

    if (fields.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              Text('No Voter ID details found',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            ...fields.entries.map((entry) {
              return _buildRow(context, entry.key, entry.value);
            }),
            if (voter.isEpicNumberValid) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Voter ID is Valid',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ] else if (voter.epicNumber != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Invalid Voter ID Format',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
}
