/// Parsed passport details extracted from OCR text.
class PassportDetails {
  final String? name;
  final String? surname;
  final String? nationality;
  final String? dob;
  final String? gender;
  final String? passportNumber;
  final String? dateOfIssue;
  final String? dateOfExpiry;
  final String? placeOfIssue;
  final String? placeOfBirth;
  final String? fatherName;
  final String rawText;

  const PassportDetails({
    this.name,
    this.surname,
    this.nationality,
    this.dob,
    this.gender,
    this.passportNumber,
    this.dateOfIssue,
    this.dateOfExpiry,
    this.placeOfIssue,
    this.placeOfBirth,
    this.fatherName,
    required this.rawText,
  });

  /// Parses OCR text from a passport into structured fields.
  factory PassportDetails.fromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? name;
    String? surname;
    String? nationality;
    String? dob;
    String? gender;
    String? passportNumber;
    String? dateOfIssue;
    String? dateOfExpiry;
    String? placeOfIssue;
    String? placeOfBirth;
    String? fatherName;

    final datePattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})');
    // Indian passport: starts with letter, followed by 7 digits
    final passportNumPattern = RegExp(r'\b([A-Z]\d{7})\b');
    final genderPattern = RegExp(r'\b(MALE|FEMALE|M|F)\b', caseSensitive: false);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // Passport number
      if (passportNumber == null) {
        final match = passportNumPattern.firstMatch(line);
        if (match != null) {
          passportNumber = match.group(1);
          continue;
        }
      }

      // Surname
      if (upper.contains('SURNAME') || upper.contains('SUR NAME')) {
        surname = _extractValue(line, lines, i);
        continue;
      }

      // Given name
      if (upper.contains('GIVEN NAME') || upper.contains('GIVEN NAMES')) {
        name = _extractValue(line, lines, i);
        continue;
      }

      // Name (generic)
      if (upper.contains('NAME') && !upper.contains('SUR') && !upper.contains('GIVEN') && !upper.contains('FATHER') && name == null) {
        name = _extractValue(line, lines, i);
        continue;
      }

      // Nationality
      if (upper.contains('NATIONALITY')) {
        nationality = _extractValue(line, lines, i);
        if (nationality == null || nationality.isEmpty) nationality = 'INDIAN';
        continue;
      }

      // Gender / Sex
      if (upper.contains('SEX') || upper.contains('GENDER')) {
        final match = genderPattern.firstMatch(line);
        if (match != null) {
          final g = match.group(1)!.toUpperCase();
          gender = (g == 'M' || g == 'MALE') ? 'Male' : 'Female';
        }
        continue;
      }

      // Date of Birth
      if (upper.contains('BIRTH') || upper.contains('DOB')) {
        final match = datePattern.firstMatch(line);
        if (match != null) dob = match.group(1);
        continue;
      }

      // Place of Birth
      if (upper.contains('PLACE OF BIRTH')) {
        placeOfBirth = _extractValue(line, lines, i);
        continue;
      }

      // Date of Issue
      if (upper.contains('ISSUE') && !upper.contains('PLACE')) {
        final match = datePattern.firstMatch(line);
        if (match != null) dateOfIssue = match.group(1);
        continue;
      }

      // Date of Expiry
      if (upper.contains('EXPIRY') || upper.contains('EXPIRATION') || upper.contains('VALID')) {
        final match = datePattern.firstMatch(line);
        if (match != null) dateOfExpiry = match.group(1);
        continue;
      }

      // Place of Issue
      if (upper.contains('PLACE OF ISSUE')) {
        placeOfIssue = _extractValue(line, lines, i);
        continue;
      }

      // Father name
      if (upper.contains('FATHER') || upper.contains("FATHER'S")) {
        fatherName = _extractValue(line, lines, i);
        continue;
      }
    }

    return PassportDetails(
      name: name,
      surname: surname,
      nationality: nationality,
      dob: dob,
      gender: gender,
      passportNumber: passportNumber,
      dateOfIssue: dateOfIssue,
      dateOfExpiry: dateOfExpiry,
      placeOfIssue: placeOfIssue,
      placeOfBirth: placeOfBirth,
      fatherName: fatherName,
      rawText: text,
    );
  }

  static String? _extractValue(String line, List<String> lines, int i) {
    // Split on colon only (not hyphen, which breaks dates)
    final colonIdx = line.indexOf(':');
    if (colonIdx != -1) {
      final val = line.substring(colonIdx + 1).trim();
      if (val.isNotEmpty) return val;
    }
    if (i + 1 < lines.length) return lines[i + 1];
    return null;
  }

  /// Validates passport number format (letter + 7 digits).
  bool get isPassportNumberValid =>
      passportNumber != null && RegExp(r'^[A-Z]\d{7}$').hasMatch(passportNumber!);

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (passportNumber != null) map['Passport No.'] = passportNumber!;
    if (surname != null) map['Surname'] = surname!;
    if (name != null) map['Given Name'] = name!;
    if (nationality != null) map['Nationality'] = nationality!;
    if (dob != null) map['Date of Birth'] = dob!;
    if (gender != null) map['Gender'] = gender!;
    if (placeOfBirth != null) map['Place of Birth'] = placeOfBirth!;
    if (dateOfIssue != null) map['Date of Issue'] = dateOfIssue!;
    if (dateOfExpiry != null) map['Date of Expiry'] = dateOfExpiry!;
    if (placeOfIssue != null) map['Place of Issue'] = placeOfIssue!;
    if (fatherName != null) map['Father Name'] = fatherName!;
    return map;
  }
}
