/// Parsed Aadhaar card details extracted from OCR text.
/// Supports both old format (English-only) and new bilingual format
/// (Hindi + English labels like "नाम / Name", "पिता का नाम / Father's Name").
class AadhaarDetails {
  final String? name;
  final String? fatherName;
  final String? dob;
  final String? gender;
  final String? aadhaarNumber;
  final String? address;
  final String rawText;

  const AadhaarDetails({
    this.name,
    this.fatherName,
    this.dob,
    this.gender,
    this.aadhaarNumber,
    this.address,
    required this.rawText,
  });

  /// Parses OCR text into structured Aadhaar fields.
  /// Handles:
  /// - Old format: English-only labels (DOB, S/O, Address)
  /// - New bilingual format: Hindi+English labels (नाम / Name, पिता का नाम / Father's Name)
  /// - Masked Aadhaar: XXXX XXXX 1234
  factory AadhaarDetails.fromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? name;
    String? fatherName;
    String? dob;
    String? gender;
    String? aadhaarNumber;
    final addressLines = <String>[];

    final aadhaarPattern = RegExp(r'(?<!\d)(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})(?!\d)');
    final aadhaarPatternNoSep = RegExp(r'(?<!\d)(\d{12})(?!\d)');
    final aadhaarPatternPartial = RegExp(r'(?<!\d)(\d{4,8})[\s\-]+(\d{4,8})(?!\d)');
    final dobPattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})');
    final yearPattern = RegExp(r'(\d{4})');
    final genderPattern = RegExp(r'\b(Male|Female|MALE|FEMALE|Transgender)\b', caseSensitive: false);

    // Bilingual label patterns — Hindi keywords matched as plain contains checks,
    // English keywords matched via regex to avoid raw-string escape issues.
    final nameLabelEnPattern = RegExp(r'Name\s*:', caseSensitive: false);
    final fatherLabelEnPattern = RegExp(r"(Father.?s?\s*Name|S/O|D/O|W/O|C/O)", caseSensitive: false);
    final dobLabelPattern = RegExp(
      r'(DOB|Date\s*of\s*Birth|Year\s*of\s*Birth|YOB|Birth)',
      caseSensitive: false,
    );
    final addressLabelPattern = RegExp(r'(Address|Add\b)', caseSensitive: false);
    final headerPattern = RegExp(
      r'(Government|India|Aadhaar|UIDAI|Unique|Identification|Authority|XXXX)',
      caseSensitive: false,
    );

    // Hindi label substrings for bilingual new-format cards
    const hindiName = 'नाम';
    const hindiFather = 'पिता';
    const hindiDob = 'जन्म';
    const hindiAddress = 'पता';

    final consumed = <int>{};
    int? dobLineIdx;
    int? genderLineIdx;
    int? fatherLineIdx;
    int? addressStartIdx;
    int? aadhaarLineIdx;

    // Pass 1: Find all labeled/known fields
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Aadhaar number (standard with separators)
      if (aadhaarPattern.hasMatch(line) || aadhaarPatternNoSep.hasMatch(line)) {
        final match = aadhaarPattern.firstMatch(line) ?? aadhaarPatternNoSep.firstMatch(line);
        aadhaarNumber = match?.group(0);
        aadhaarLineIdx = i;
        consumed.add(i);
        continue;
      }
      // Partial separator: "5689 23658955"
      if (aadhaarPatternPartial.hasMatch(line)) {
        final match = aadhaarPatternPartial.firstMatch(line)!;
        final combined = '${match.group(1)}${match.group(2)}';
        if (combined.length == 12 && RegExp(r'^\d{12}$').hasMatch(combined)) {
          aadhaarNumber = match.group(0);
          aadhaarLineIdx = i;
          consumed.add(i);
          continue;
        }
      }

      // DOB — bilingual (Hindi) or English label
      final isHindiDob = line.contains(hindiDob);
      if (isHindiDob || dobLabelPattern.hasMatch(line)) {
        final dobMatch = dobPattern.firstMatch(line);
        if (dobMatch != null) {
          dob = dobMatch.group(0);
        } else if (i + 1 < lines.length) {
          final nextDob = dobPattern.firstMatch(lines[i + 1]);
          if (nextDob != null) {
            dob = nextDob.group(0);
            consumed.add(i + 1);
          } else {
            final yearMatch = yearPattern.firstMatch(line);
            if (yearMatch != null) dob = yearMatch.group(0);
          }
        }
        dobLineIdx = i;
        consumed.add(i);
        continue;
      }
      if (dob == null && dobPattern.hasMatch(line)) {
        dob = dobPattern.firstMatch(line)?.group(0);
        dobLineIdx = i;
        consumed.add(i);
        continue;
      }

      // Gender
      if (genderPattern.hasMatch(line)) {
        gender = genderPattern.firstMatch(line)?.group(0);
        genderLineIdx = i;
        consumed.add(i);
        continue;
      }

      // Name — bilingual "नाम / Name" or English "Name:"
      final isHindiName = line.contains(hindiName);
      if ((isHindiName || nameLabelEnPattern.hasMatch(line)) && name == null) {
        name = _extractLabelValue(line, lines, i);
        if (name != null) consumed.add(i);
        continue;
      }

      // Father/Husband — bilingual "पिता का नाम / Father's Name" or English
      final isHindiFather = line.contains(hindiFather);
      if (isHindiFather || fatherLabelEnPattern.hasMatch(line)) {
        fatherName = _extractLabelValue(line, lines, i);
        if (fatherName == null || fatherName.isEmpty) {
          fatherName = line
              .replaceAll(RegExp(r'(S/O|D/O|W/O|C/O)[:\s]*', caseSensitive: false), '')
              .trim();
          if (fatherName.isEmpty && i + 1 < lines.length) {
            fatherName = lines[i + 1];
            consumed.add(i + 1);
          }
        }
        fatherLineIdx = i;
        consumed.add(i);
        continue;
      }

      // Address — bilingual "पता / Address" or English
      final isHindiAddress = line.contains(hindiAddress);
      if (isHindiAddress || addressLabelPattern.hasMatch(line)) {
        addressStartIdx = i;
        consumed.add(i);
        final afterLabel = line
            .replaceAll(RegExp(r'(Address|Add)[:\s]*', caseSensitive: false), '')
            .replaceAll(hindiAddress, '')
            .trim();
        if (afterLabel.isNotEmpty) addressLines.add(afterLabel);
        continue;
      }

      // Header lines
      if (headerPattern.hasMatch(line)) {
        consumed.add(i);
        continue;
      }
    }

    // Pass 2: Collect address lines (after address label, before aadhaar number)
    if (addressStartIdx != null) {
      for (int i = addressStartIdx + 1; i < lines.length; i++) {
        if (consumed.contains(i)) continue;
        if (aadhaarLineIdx != null && i >= aadhaarLineIdx) break;
        addressLines.add(lines[i]);
        consumed.add(i);
      }
    }

    // Pass 3: Find name — first unconsumed line before dob/gender/father/address
    if (name == null) {
      final firstFieldIdx = [dobLineIdx, genderLineIdx, fatherLineIdx, addressStartIdx, aadhaarLineIdx]
          .whereType<int>()
          .fold<int>(lines.length, (min, idx) => idx < min ? idx : min);

      for (int i = 0; i < firstFieldIdx; i++) {
        if (consumed.contains(i)) continue;
        final line = lines[i];
        if (line.length >= 2 &&
            line.length <= 40 &&
            RegExp(r'[A-Za-z]').hasMatch(line) &&
            !RegExp(r'^\d+$').hasMatch(line) &&
            !line.contains(':')) {
          name = line;
          consumed.add(i);
          break;
        }
      }
    }

    return AadhaarDetails(
      name: name,
      fatherName: fatherName,
      dob: dob,
      gender: gender,
      aadhaarNumber: aadhaarNumber,
      address: addressLines.isNotEmpty ? addressLines.join(', ') : null,
      rawText: text,
    );
  }

  /// Extracts value after a label — checks same line (after colon or slash) then next line.
  static String? _extractLabelValue(String line, List<String> lines, int i) {
    // After colon
    final colonIdx = line.indexOf(':');
    if (colonIdx != -1) {
      final val = line.substring(colonIdx + 1).trim();
      if (val.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(val)) return val;
    }
    // After last slash (bilingual: "नाम / Name RAM KUMAR" or value after slash)
    final slashIdx = line.lastIndexOf('/');
    if (slashIdx != -1) {
      final afterSlash = line.substring(slashIdx + 1).trim();
      if (afterSlash.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(afterSlash)) return afterSlash;
    }
    // Next line
    if (i + 1 < lines.length) {
      final next = lines[i + 1].trim();
      if (next.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(next) && next.length >= 2) return next;
    }
    return null;
  }

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (name != null) map['Name'] = name!;
    if (fatherName != null) map['Father/Husband'] = fatherName!;
    if (dob != null) map['DOB'] = dob!;
    if (gender != null) map['Gender'] = gender!;
    if (address != null) map['Address'] = address!;
    if (aadhaarNumber != null) map['Aadhaar No.'] = aadhaarNumber!;
    return map;
  }
}
