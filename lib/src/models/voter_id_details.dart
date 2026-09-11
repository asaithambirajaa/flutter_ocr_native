import '../validators/document_number_validator.dart';

/// Parsed Voter ID (EPIC) details extracted from OCR text.
/// Supports both old format (ELECTOR'S NAME, FATHER'S NAME) and new format
/// (Name:, Father's Name:, Husband's Name:, Age:, Sex:).
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
  /// Handles:
  /// - Old format: ELECTOR'S NAME, FATHER'S NAME, printed on card
  /// - New format: Name, Date of Birth, Sex, Relative's Name, Address
  /// - Bilingual cards: Tamil + English (filters to English-only lines)
  /// - Age → approximate birth year when DOB not present
  factory VoterIdDetails.fromText(String text) {
    // Filter to English-only lines (skip Tamil/Hindi)
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && _isEnglishLine(l))
        .toList();

    String? name;
    String? fatherName;
    String? dob;
    String? gender;
    String? epicNumber;
    final addressLines = <String>[];

    // Extract EPIC number first from full text
    epicNumber = DocumentNumberValidator.extractVoterId(text);

    final datePattern = RegExp(r'\b(\d{1,2}[/\-]\d{1,2}[/\-]\d{4})\b');
    final genderPattern = RegExp(r'\b(Male|Female|MALE|FEMALE)\b', caseSensitive: false);
    final agePattern = RegExp(r'\bAGE\s*:?\s*(\d{1,3})\b', caseSensitive: false);

    // Find date of birth from full text
    final dobMatch = datePattern.firstMatch(text);
    if (dobMatch != null) dob = dobMatch.group(1);

    // Find gender from full text
    final genderMatch = genderPattern.firstMatch(text);
    if (genderMatch != null) gender = _normalizeGender(genderMatch.group(1)!);

    // Track which lines have been consumed as values
    final consumedLines = <int>{};
    bool foundAddress = false;

    for (int i = 0; i < lines.length; i++) {
      if (consumedLines.contains(i)) continue;

      final line = lines[i];
      final upper = line.toUpperCase();

      // Helper to get next non-consumed line as value
      String? getNextValue() {
        for (int j = i + 1; j < lines.length && j <= i + 2; j++) {
          if (!consumedLines.contains(j)) {
            final val = lines[j].trim();
            // Skip if it looks like another label
            if (_isLabel(val)) continue;
            consumedLines.add(j);
            return val;
          }
        }
        return null;
      }

      // ── EPIC Number ──────────────────────────────────────────────────────
      if (upper.contains('EPIC')) {
        // Try to extract from same line first
        final extracted = DocumentNumberValidator.extractVoterId(line);
        if (extracted != null) {
          epicNumber ??= extracted;
        } else {
          // Value on next line
          final val = getNextValue();
          if (val != null) {
            final ext = DocumentNumberValidator.extractVoterId(val);
            if (ext != null) epicNumber ??= ext;
          }
        }
        continue;
      }

      // ── Name ─────────────────────────────────────────────────────────────
      // Match "Name" but not "Father's Name", "Relative's Name", "Husband's Name"
      // Also handle split labels: "Elector's" on one line, "Name" on next
      if (_isNameLabel(upper) || upper == "ELECTOR'S" || upper == 'ELECTOR') {
        // Check if value is on same line after colon
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          final val = line.substring(colonIdx + 1).trim();
          if (val.length > 2 && !_isLabel(val)) {
            name ??= val;
            continue;
          }
        }
        // Value on next line (skip "Name" if it's a continuation of split label)
        final val = getNextValue();
        if (val != null && val.toUpperCase() != 'NAME' && val.length > 2) name ??= val;
        continue;
      }

      // ── Father / Husband / Relative / Relation ─────────────────────────
      // Also handle split labels: "Relation's" on one line, "Name" on next
      if (upper.contains('FATHER') || upper.contains('HUSBAND') || 
          upper.contains('RELATIVE') || upper.contains('RELATION')) {
        // Check if value is on same line after colon
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          final val = line.substring(colonIdx + 1).trim();
          if (val.length > 2 && !_isLabel(val)) {
            fatherName ??= val;
            continue;
          }
        }
        // Value on next line - skip "Name" if it's a continuation of split label
        final val = getNextValue();
        if (val != null && val.toUpperCase() != 'NAME' && val.length > 2) {
          fatherName ??= val;
        }
        continue;
      }

      // ── S/O, D/O, W/O ────────────────────────────────────────────────────
      if (upper.contains('S/O') || upper.contains('D/O') || upper.contains('W/O')) {
        final val = line.replaceAll(RegExp(r'(S/O|D/O|W/O)[:\s]*', caseSensitive: false), '').trim();
        if (val.length > 2) {
          fatherName ??= val;
        } else {
          final nextVal = getNextValue();
          if (nextVal != null && nextVal.length > 2) fatherName ??= nextVal;
        }
        continue;
      }

      // ── Date of Birth ────────────────────────────────────────────────────
      if (upper.contains('DATE') && upper.contains('BIRTH') || upper.contains('DOB') || upper.startsWith('D.O.B')) {
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          final val = line.substring(colonIdx + 1).trim();
          final dm = datePattern.firstMatch(val);
          if (dm != null) dob ??= dm.group(1);
        }
        if (dob == null) {
          final val = getNextValue();
          if (val != null) {
            final dm = datePattern.firstMatch(val);
            if (dm != null) dob = dm.group(1);
          }
        }
        continue;
      }

      // ── Gender / Sex ─────────────────────────────────────────────────────
      if (upper.startsWith('SEX') || upper.startsWith('GENDER')) {
        // Check same line
        final gm = genderPattern.firstMatch(line);
        if (gm != null) {
          gender ??= _normalizeGender(gm.group(1)!);
        } else {
          final val = getNextValue();
          if (val != null) {
            final gm2 = genderPattern.firstMatch(val);
            if (gm2 != null) gender ??= _normalizeGender(gm2.group(1)!);
          }
        }
        continue;
      }

      // ── Age → approximate DOB ────────────────────────────────────────────
      if (dob == null && agePattern.hasMatch(line)) {
        final ageMatch = agePattern.firstMatch(line)!;
        final age = int.tryParse(ageMatch.group(1)!);
        if (age != null && age > 0 && age < 120) {
          dob = (DateTime.now().year - age).toString();
        }
        continue;
      }

      // ── Address ──────────────────────────────────────────────────────────
      if (upper.contains('ADDRESS')) {
        foundAddress = true;
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1) {
          final val = line.substring(colonIdx + 1).trim();
          if (val.isNotEmpty) addressLines.add(val);
        }
        continue;
      }

      if (foundAddress) {
        // Stop collecting address when we hit another field
        if (_isLabel(line) || datePattern.hasMatch(line)) {
          foundAddress = false;
          continue;
        }
        addressLines.add(line);
        continue;
      }

      // ── Skip header lines ────────────────────────────────────────────────
      if (upper.contains('ELECTION') || upper.contains('COMMISSION') ||
          upper.contains('INDIA') || upper.contains('VOTER') ||
          upper.contains('ELECTORAL') || upper.contains('PHOTO') ||
          upper.contains('IDENTITY') || upper.contains('CARD')) {
        continue;
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

  /// Returns true if the line looks like a field label (not a value).
  /// Only returns true for lines that are PRIMARILY labels, not values that
  /// happen to contain a keyword.
  static bool _isLabel(String line) {
    final upper = line.toUpperCase().trim();
    // Short lines that are just labels
    if (upper == 'NAME' || upper == 'EPIC NO' || upper == 'EPIC NO.' ||
        upper == 'DOB' || upper == 'SEX' || upper == 'GENDER' ||
        upper == 'ADDRESS' || upper == 'AGE') {
      return true;
    }
    // Lines starting with label patterns
    if (upper.startsWith('ELECTOR') && upper.contains('NAME')) return true;
    if (upper.startsWith('FATHER') && upper.contains('NAME')) return true;
    if (upper.startsWith('HUSBAND') && upper.contains('NAME')) return true;
    if (upper.startsWith('RELATIVE') && upper.contains('NAME')) return true;
    if (upper.startsWith('RELATION') && upper.contains('NAME')) return true;
    if (upper.startsWith('DATE') && upper.contains('BIRTH')) return true;
    if (upper.startsWith('DATE OF BIRTH')) return true;
    if (upper.startsWith('EPIC')) return true;
    if (upper.startsWith('ADDRESS')) return true;
    if (upper.startsWith('SEX')) return true;
    if (upper.startsWith('GENDER')) return true;
    if (upper.startsWith('DOB')) return true;
    if (upper.startsWith('D.O.B')) return true;
    if (upper.startsWith('AGE')) return true;
    if (upper.startsWith('NAME:') || upper.startsWith('NAME :')) return true;
    // Also check for just "Relative's Name" or "Relation's Name" without starting check
    if (upper.contains('RELATIVE') && upper.contains('NAME') && upper.length < 25) return true;
    if (upper.contains('RELATION') && upper.contains('NAME') && upper.length < 25) return true;
    return false;
  }

  /// Returns true if this is a "Name" label (voter's name, not relative's name).
  static bool _isNameLabel(String upper) {
    // Must contain NAME but not FATHER/HUSBAND/RELATIVE/RELATION
    if (!upper.contains('NAME')) return false;
    if (upper.contains('FATHER')) return false;
    if (upper.contains('HUSBAND')) return false;
    if (upper.contains('RELATIVE')) return false;
    if (upper.contains('RELATION')) return false;
    if (upper.contains('ELECTOR')) return true; // ELECTOR'S NAME
    // Just "Name" or "Name:" at start
    return upper.startsWith('NAME') || upper == 'NAME';
  }

  /// Returns true if line contains primarily English characters.
  /// Filters out Tamil, Hindi, and other non-Latin scripts.
  static bool _isEnglishLine(String line) {
    if (line.isEmpty) return false;
    // Count ASCII letters vs non-ASCII
    int ascii = 0, nonAscii = 0;
    for (final c in line.runes) {
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
        ascii++;
      } else if (c > 127) {
        nonAscii++;
      }
    }
    // Keep if has ASCII letters and not dominated by non-ASCII
    return ascii > 0 && ascii >= nonAscii;
  }

  static String _normalizeGender(String raw) {
    final upper = raw.toUpperCase();
    if (upper == 'M' || upper == 'MALE') return 'Male';
    if (upper == 'F' || upper == 'FEMALE') return 'Female';
    return raw;
  }

  /// Validates EPIC number format (3 letters + 7 digits = 10 chars).
  bool get isEpicNumberValid =>
      epicNumber != null && RegExp(r'^[A-Z]{3}\d{7}$').hasMatch(epicNumber!);

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
