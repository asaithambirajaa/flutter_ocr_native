import 'dart:developer';

import '../validators/document_number_validator.dart';

/// Parsed Voter ID (EPIC) details extracted from OCR text.
class VoterIdDetails {
  final String? name;
  final String? fatherName;
  final String? dob;
  final String? gender;
  final String? epicNumber;
  final String? address;
  final String rawText;

  const VoterIdDetails({
    this.name,
    this.fatherName,
    this.dob,
    this.gender,
    this.epicNumber,
    this.address,
    required this.rawText,
  });

  /// Parses OCR text from a Voter ID into structured fields.
  factory VoterIdDetails.fromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? name;
    String? fatherName;
    String? dob;
    String? gender;
    String? epicNumber;
    final addressLines = <String>[];

    // Extract EPIC number first
    epicNumber = DocumentNumberValidator.extractVoterId(text);

    // Simple patterns for common fields
    final datePattern = RegExp(r'\b(\d{1,2}[/\-]\d{1,2}[/\-]\d{4})\b');
    final genderPattern = RegExp(r'\b(Male|Female)\b', caseSensitive: false);

    // Find date of birth
    final dobMatch = datePattern.firstMatch(text);
    if (dobMatch != null) {
      dob = dobMatch.group(1);
    }

    // Find gender
    final genderMatch = genderPattern.firstMatch(text);
    if (genderMatch != null) {
      gender = genderMatch.group(1);
    }

    // Extract name with better filtering
    final potentialNameLines = <String>[];

    log('=== NAME EXTRACTION DEBUG ===');
    log('Processing ${lines.length} lines for name extraction:');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      log('Line $i: "$line"');

      // Check if line contains name after a label
      if (upper.contains('ELECTOR') && upper.contains('NAME')) {
        // Extract name after "Elector's Name" or similar
        final nameMatch =
            RegExp(r"ELECTOR'?S?\s*NAME\s*:?\s*(.+)", caseSensitive: false)
                .firstMatch(line);
        if (nameMatch != null) {
          final extractedName = nameMatch.group(1)?.trim();
          if (extractedName != null &&
              extractedName.isNotEmpty &&
              extractedName.length > 2) {
            log('  -> EXTRACTED NAME FROM LABEL: "$extractedName"');
            potentialNameLines.add(extractedName);
            continue;
          }
        }
      }

      // Check for other name labels
      if (upper.contains('NAME')) {
        final namePatterns = [
          RegExp(r'NAME\s*:?\s*(.+)', caseSensitive: false),
          RegExp(r'ELECTOR\s*NAME\s*:?\s*(.+)', caseSensitive: false),
          RegExp(r'VOTER\s*NAME\s*:?\s*(.+)', caseSensitive: false),
        ];

        for (final pattern in namePatterns) {
          final match = pattern.firstMatch(line);
          if (match != null) {
            final extractedName = match.group(1)?.trim();
            if (extractedName != null &&
                extractedName.isNotEmpty &&
                extractedName.length > 2) {
              log('  -> EXTRACTED NAME FROM PATTERN: "$extractedName"');
              potentialNameLines.add(extractedName);
              break;
            }
          }
        }
        continue;
      }

      // Skip other header/system lines (but not lines with NAME)
      if (upper.contains('ELECTION') ||
          upper.contains('COMMISSION') ||
          upper.contains('INDIA') ||
          upper.contains('VOTER') ||
          upper.contains('EPIC') ||
          upper.contains('ELECTORAL') ||
          upper.contains('PHOTO') ||
          upper.contains('IDENTITY') ||
          upper.contains('CARD') ||
          upper.contains('ID NO') ||
          upper.contains('NUMBER') ||
          upper.contains('DOB') ||
          upper.contains('AGE') ||
          upper.contains('SEX') ||
          upper.contains('ADDRESS') ||
          upper.contains('ADD')) {
        log('  -> SKIPPED: Contains header/system text');
        continue;
      }

      // Extract father/husband name from labeled lines
      if (upper.contains('FATHER') ||
          upper.contains('HUSBAND') ||
          upper.contains('S/O') ||
          upper.contains('D/O') ||
          upper.contains('W/O')) {
        final fatherMatch = RegExp(
          r"(FATHER'?S?\s*NAME|HUSBAND'?S?\s*NAME|S/O|D/O|W/O)[:\s]*(.*)",
          caseSensitive: false,
        ).firstMatch(line);
        if (fatherMatch != null) {
          final extracted = fatherMatch.group(2)?.trim();
          if (extracted != null && extracted.isNotEmpty && extracted.length > 2) {
            fatherName = extracted;
          } else if (i + 1 < lines.length) {
            fatherName = lines[i + 1];
          }
        }
        log('  -> SKIPPED: Father/Husband label');
        continue;
      }

      // Skip EPIC numbers and dates
      if (RegExp(r'^[A-Z]{2,3}\s*\d{6,7}\s*$')
              .hasMatch(line.replaceAll(' ', '')) ||
          datePattern.hasMatch(line) ||
          genderPattern.hasMatch(line)) {
        log('  -> SKIPPED: EPIC/date/gender pattern');
        continue;
      }

      // Must be reasonable length and contain only letters/spaces/dots
      if (line.length >= 3 &&
          line.length <= 50 &&
          RegExp(r'^[A-Za-z\s.]+$').hasMatch(line)) {
        log('  -> POTENTIAL NAME: "$line"');
        potentialNameLines.add(line);
      } else {
        log('  -> SKIPPED: Length ${line.length} or invalid characters');
      }
    }

    log('Found ${potentialNameLines.length} potential name lines:');
    for (int i = 0; i < potentialNameLines.length; i++) {
      log('  Potential $i: "${potentialNameLines[i]}"');
    }

    // Extract name from potential lines
    for (final line in potentialNameLines) {
      log('Evaluating potential name: "$line"');

      // Skip very short or single letter lines
      if (line.length < 2) {
        log('  -> SKIPPED: Too short (${line.length} chars)');
        continue;
      }

      // Skip if it's just initials
      if (RegExp(r'^[A-Z]\s+[A-Z]\s*$').hasMatch(line)) {
        log('  -> SKIPPED: Just initials');
        continue;
      }

      // First good line is the name
      if (name == null) {
        name = line;
        log('  -> SELECTED AS NAME: "$line"');
      } else if (fatherName == null) {
        fatherName = line;
        log('  -> SELECTED AS FATHER NAME: "$line"');
      }
    }

    // Fallback: if no name found, take the longest potential line
    if (name == null && potentialNameLines.isNotEmpty) {
      potentialNameLines.sort((a, b) => b.length.compareTo(a.length));
      name = potentialNameLines.first;
      log('FALLBACK: Selected longest line as name: "$name"');
    }

    log('Final extracted name: "$name"');
    log('Final extracted father name: "$fatherName"');
    log('=============================');

    // Extract address - lines after name/father that contain address-like content
    bool foundAddress = false;
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('ADDRESS') || upper.contains('ADD:')) {
        foundAddress = true;
        final addressPart = line
            .replaceAll(
                RegExp(r'(ADDRESS|ADD)[:\s]*', caseSensitive: false), '')
            .trim();
        if (addressPart.isNotEmpty) {
          addressLines.add(addressPart);
        }
        continue;
      }

      if (foundAddress &&
          !genderPattern.hasMatch(line) &&
          !datePattern.hasMatch(line)) {
        // Stop collecting address if we hit gender or date
        if (upper.contains('MALE') ||
            upper.contains('FEMALE') ||
            upper.contains('DOB')) {
          break;
        }
        addressLines.add(line);
      }
    }

    return VoterIdDetails(
      name: name,
      fatherName: fatherName,
      dob: dob,
      gender: gender,
      epicNumber: epicNumber,
      address: addressLines.isNotEmpty ? addressLines.join(', ') : null,
      rawText: text,
    );
  }

  /// Validates EPIC number format (3 letters + 6-7 digits).
  bool get isEpicNumberValid =>
      epicNumber != null && RegExp(r'^[A-Z]{3}\d{6,7}$').hasMatch(epicNumber!);

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (epicNumber != null) map['EPIC No.'] = epicNumber!;
    if (name != null) map['Name'] = name!;
    if (fatherName != null) map['Father/Husband'] = fatherName!;
    if (dob != null) map['DOB'] = dob!;
    if (gender != null) map['Gender'] = gender!;
    if (address != null) map['Address'] = address!;
    return map;
  }

  /// Returns a map of primary fields: EPIC No., Name, and Address (for quick display).
  Map<String, String> toPrimaryFieldsMap() {
    final map = <String, String>{};
    if (epicNumber != null) map['EPIC No.'] = epicNumber!;
    if (name != null) map['Name'] = name!;
    if (address != null) map['Address'] = address!;
    return map;
  }
}
