/// Parsed Aadhaar card details extracted from OCR text.
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
    // Also match partial separators like "5689 23658955" or "56892365 8955"
    final aadhaarPatternPartial = RegExp(r'(?<!\d)(\d{4,8})[\s\-]+(\d{4,8})(?!\d)');
    final dobPattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})');
    final yearPattern = RegExp(r'(\d{4})');
    final genderPattern = RegExp(r'\b(Male|Female|MALE|FEMALE|Transgender)\b', caseSensitive: false);
    final dobLabelPattern = RegExp(r'(DOB|Date of Birth|Year of Birth|YOB|Birth)', caseSensitive: false);
    final fatherLabelPattern = RegExp(r'(S/O|D/O|W/O|C/O)', caseSensitive: false);
    final addressLabelPattern = RegExp(r'(Address|Add\b)', caseSensitive: false);
    final headerPattern = RegExp(
      r'(Government|India|Aadhaar|UIDAI|Unique|Identification|Authority|XXXX)',
      caseSensitive: false,
    );

    // Track which lines are "consumed" by known fields
    final consumed = <int>{};
    int? dobLineIdx;
    int? genderLineIdx;
    int? fatherLineIdx;
    int? addressStartIdx;
    int? aadhaarLineIdx;

    // Pass 1: Find all labeled/known fields
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Aadhaar number
      if (aadhaarPattern.hasMatch(line) || aadhaarPatternNoSep.hasMatch(line)) {
        final match = aadhaarPattern.firstMatch(line) ?? aadhaarPatternNoSep.firstMatch(line);
        aadhaarNumber = match?.group(0);
        aadhaarLineIdx = i;
        consumed.add(i);
        continue;
      }
      // Partial separator: "5689 23658955" or "56892365 8955"
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

      // DOB
      if (dobLabelPattern.hasMatch(line)) {
        final dobMatch = dobPattern.firstMatch(line);
        if (dobMatch != null) {
          dob = dobMatch.group(0);
        } else {
          final yearMatch = yearPattern.firstMatch(line);
          if (yearMatch != null) dob = yearMatch.group(0);
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

      // Father/Husband
      if (fatherLabelPattern.hasMatch(line)) {
        fatherName = line
            .replaceAll(RegExp(r'(S/O|D/O|W/O|C/O)[:\s]*', caseSensitive: false), '')
            .trim();
        if (fatherName.isEmpty && i + 1 < lines.length) {
          fatherName = lines[i + 1];
          consumed.add(i + 1);
        }
        fatherLineIdx = i;
        consumed.add(i);
        continue;
      }

      // Address label
      if (addressLabelPattern.hasMatch(line)) {
        addressStartIdx = i;
        consumed.add(i);
        final afterLabel = line
            .replaceAll(RegExp(r'(Address|Add)[:\s]*', caseSensitive: false), '')
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

    // Pass 3: Find name — first unconsumed line that appears BEFORE dob/gender/father/address
    // Name is typically the first meaningful text after the header
    final firstFieldIdx = [dobLineIdx, genderLineIdx, fatherLineIdx, addressStartIdx, aadhaarLineIdx]
        .whereType<int>()
        .fold<int>(lines.length, (min, idx) => idx < min ? idx : min);

    for (int i = 0; i < firstFieldIdx; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];
      // Name: at least 2 chars, mostly letters/spaces, not a number, not too long
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
