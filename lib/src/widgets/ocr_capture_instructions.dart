import 'package:flutter/material.dart';

/// Shows capture/upload instructions before document scanning.
/// Guides users on best angle, lighting, and document clarity.
class OcrCaptureInstructions extends StatelessWidget {
  /// Title shown at the top. Default: "Document Capture Tips"
  final String? title;

  /// Whether to show the instruction as a bottom sheet.
  /// If false, renders inline as a widget.
  final bool asBottomSheet;

  /// Called when user taps "Continue" / "Got it".
  final VoidCallback? onContinue;

  /// Custom instructions to add/replace defaults.
  final List<OcrInstruction>? customInstructions;

  const OcrCaptureInstructions({
    super.key,
    this.title,
    this.asBottomSheet = false,
    this.onContinue,
    this.customInstructions,
  });

  /// Shows instructions as a modal bottom sheet.
  /// Returns true if user tapped "Continue", null if dismissed.
  static Future<bool?> showAsBottomSheet(
    BuildContext context, {
    String? title,
    List<OcrInstruction>? customInstructions,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => OcrCaptureInstructions(
        title: title,
        customInstructions: customInstructions,
        asBottomSheet: true,
        onContinue: () => Navigator.pop(context, true),
      ),
    );
  }

  /// Shows instructions as a dialog.
  /// Returns true if user tapped "Continue".
  static Future<bool?> showAsDialog(
    BuildContext context, {
    String? title,
    List<OcrInstruction>? customInstructions,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title ?? 'Document Capture Tips'),
        content: SingleChildScrollView(
          child: OcrCaptureInstructions(
            customInstructions: customInstructions,
            onContinue: () => Navigator.pop(context, true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  static List<OcrInstruction> get _defaultInstructions => const [
        OcrInstruction(
          icon: Icons.crop_free,
          title: 'Fill the Frame',
          description: 'Document should cover 70-80% of the image. '
              'Avoid too much background.',
          color: Colors.blue,
        ),
        OcrInstruction(
          icon: Icons.straighten,
          title: 'Keep it Flat & Straight',
          description: 'Place document on a flat surface. '
              'Capture directly from above — no tilt or angle.',
          color: Colors.green,
        ),
        OcrInstruction(
          icon: Icons.light_mode,
          title: 'Good Lighting',
          description: 'Use even, natural light. '
              'Avoid shadows, glare, and reflections on the card.',
          color: Colors.orange,
        ),
        OcrInstruction(
          icon: Icons.center_focus_strong,
          title: 'Sharp & Clear',
          description: 'Hold steady — no blur. '
              'Ensure all text on the document is clearly readable.',
          color: Colors.purple,
        ),
        OcrInstruction(
          icon: Icons.contrast,
          title: 'Dark Background',
          description: 'Place document on a dark, non-reflective surface '
              'for better edge detection and contrast.',
          color: Colors.teal,
        ),
        OcrInstruction(
          icon: Icons.do_not_disturb,
          title: 'No Obstructions',
          description: 'Remove fingers, clips, or objects covering the document. '
              'All corners must be visible.',
          color: Colors.red,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final instructions = customInstructions ?? _defaultInstructions;

    if (asBottomSheet) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title ?? 'Document Capture Tips',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Follow these tips for best OCR results',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              ...instructions.map((i) => _InstructionTile(instruction: i)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Inline widget
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: instructions.map((i) => _InstructionTile(instruction: i)).toList(),
    );
  }
}

/// Single instruction item.
class OcrInstruction {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const OcrInstruction({
    required this.icon,
    required this.title,
    required this.description,
    this.color = Colors.blue,
  });
}

class _InstructionTile extends StatelessWidget {
  final OcrInstruction instruction;

  const _InstructionTile({required this.instruction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: instruction.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(instruction.icon, color: instruction.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instruction.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  instruction.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
