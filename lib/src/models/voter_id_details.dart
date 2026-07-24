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
  /// - New format: Name:, Father's Name:, Husband's Name:, Age:, Sex:
  /// - Age → approximate birth year when DOB not present
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

    final datePattern = RegExp(r'\b(\d{1,2}[/\-]\d{1,2}[/\-]\d{4})\b');
    final genderPattern = RegExp(r'\b(Male|Female|MALE|FEMALE)\b', caseSensitive: false);
    // Sex field: M / F / MALE / FEMALE
    final sexPattern = RegExp(r'\b(M|F|MALE|FEMALE)\b', caseSensitive: false);
    // Age field: "Age: 35" or "Age : 35" or "AGE 35"
    final agePattern = RegExp(r'\bAGE\s*:?\s*(\d{1,3})\b', caseSensitive: false);

    // Find date of birth
    final dobMatch = datePattern.firstMatch(text);
    if (dobMatch != null) dob = dobMatch.group(1);

    // Find gender
    final genderMatch = genderPattern.firstMatch(text);
    if (genderMatch != null) gender = _normalizeGender(genderMatch.group(1)!);

    bool foundAddress = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // ── Name extraction ──────────────────────────────────────────────────

      // Old format: "ELECTOR'S NAME : RAM KUMAR" or "ELECTOR'S NAME" then next line
      if (upper.contains('ELECTOR') && upper.contains('NAME')) {
        final match = RegExp(r"ELECTOR'?S?\s*NAME\s*:?\s*(.+)", caseSensitive: false).firstMatch(line);
        if (match != null) {
          final val = match.group(1)?.trim();
          if (val != null && val.length > 2) {
            name ??= val;
            continue;
          }
        }
        // Value on next line
        if (i + 1 < lines.length) name ??= lines[i + 1].trim();
        continue;
      }

      // New format: "Name : RAM KUMAR" or "Name" then next line
      if (upper.startsWith('NAME') || upper.contains('VOTER NAME')) {
        final val = _extractValue(line, lines, i);
        if (val != null && val.length > 2) name ??= val;
        continue;
      }

      // ── Father / Husband name ────────────────────────────────────────────

      // Old format: "FATHER'S NAME : SHIV KUMAR"
      // New format: "Father's Name : SHIV KUMAR" or "Husband's Name : ..."
      if (upper.contains('FATHER') || upper.contains('HUSBAND')) {
        final match = RegExp(
          r"(FATHER'?S?\s*NAME|HUSBAND'?S?\s*NAME)\s*:?\s*(.*)",
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) {
          final val = match.group(2)?.trim();
          if (val != null && val.length > 2) {
            fatherName = val;
          } else if (i + 1 < lines.length) {
            fatherName = lines[i + 1].trim();
          }
        }
        continue;
      }

      // Relation labels: S/O, D/O, W/O
      if (upper.contains('S/O') || upper.contains('D/O') || upper.contains('W/O')) {
        final val = line
            .replaceAll(RegExp(r'(S/O|D/O|W/O)\s*:?\s*', caseSensitive: false), '')
            .trim();
        fatherName ??= val.isNotEmpty ? val : (i + 1 < lines.length ? lines[i + 1] : null);
        continue;
      }

      // ── Gender / Sex ─────────────────────────────────────────────────────

      // New format: "Sex : Male" or "SEX M"
      if (upper.startsWith('SEX') || upper.startsWith('GENDER')) {
        final match = sexPattern.firstMatch(line.substring(3));
        if (match != null) gender ??= _normalizeGender(match.group(1)!);
        continue;
      }

      // ── Age → approximate DOB ────────────────────────────────────────────
      // New format cards often show Age instead of DOB
      if (dob == null && agePattern.hasMatch(line)) {
        final ageMatch = agePattern.firstMatch(line)!;
        final age = int.tryParse(ageMatch.group(1)!);
        if (age != null && age > 0 && age < 120) {
          final birthYear = DateTime.now().year - age;
          dob = birthYear.toString(); // year only when full DOB unavailable
        }
        continue;
      }

      // ── Address ──────────────────────────────────────────────────────────

      if (upper.contains('ADDRESS') || upper.contains('ADD:') || upper.contains('ADDR:')) {
        foundAddress = true;
        final addressPart = line
            .replaceAll(RegExp(r'(ADDRESS|ADD|ADDR)[:\s]*', caseSensitive: false), '')
            .trim();
        if (addressPart.isNotEmpty) addressLines.add(addressPart);
        continue;
      }

      if (foundAddress) {
        if (upper.contains('MALE') ||
            upper.contains('FEMALE') ||
            upper.contains('DOB') ||
            upper.contains('AGE') ||
            upper.contains('SEX') ||
            datePattern.hasMatch(line)) {
          foundAddress = false;
          continue;
        }
        addressLines.add(line);
        continue;
      }

      // ── Skip header/system lines ─────────────────────────────────────────
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
          upper.contains('NUMBER')) {
        continue;
      }

      // ── Fallback name candidates ─────────────────────────────────────────
      // Skip EPIC numbers, dates, gender words
      if (RegExp(r'^[A-Z]{2,3}\s*\d{6,7}\s*$').hasMatch(line.replaceAll(' ', '')) ||
          datePattern.hasMatch(line) ||
          genderPattern.hasMatch(line)) {
        continue;
      }

      // Pure letter lines of reasonable length — potential name/father
      if (line.length >= 3 &&
          line.length <= 50 &&
          RegExp(r'^[A-Za-z\s.]+$').hasMatch(line)) {
        if (name == null) {
          name = line;
        } else {
          fatherName ??= line;
        }
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

  static String? _extractValue(String line, List<String> lines, int i) {
    final colonIdx = line.indexOf(':');
    if (colonIdx != -1) {
      final val = line.substring(colonIdx + 1).trim();
      if (val.isNotEmpty) return val;
    }
    if (i + 1 < lines.length) return lines[i + 1].trim();
    return null;
  }

  static String _normalizeGender(String raw) {
    final upper = raw.toUpperCase();
    if (upper == 'M' || upper == 'MALE') return 'Male';
    if (upper == 'F' || upper == 'FEMALE') return 'Female';
    return raw;
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
