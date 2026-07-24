/// Parsed passport details extracted from OCR text.
/// Supports both old booklet format (labeled fields) and new MRP/e-passport
/// format with MRZ (Machine Readable Zone) lines.
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
  /// Handles:
  /// - Old booklet format: labeled fields (Surname, Given Name, Date of Birth, etc.)
  /// - New MRP/e-passport: MRZ lines starting with "P<IND" or "P<" + country code
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
    // Indian passport: 1 letter + 7 digits
    final passportNumPattern = RegExp(r'\b([A-Z]\d{7})\b');
    final genderPattern = RegExp(r'\b(MALE|FEMALE|M|F)\b', caseSensitive: false);

    // ── MRZ parsing ──────────────────────────────────────────────────────────
    // MRZ line 1: P<IND<SURNAME<<GIVEN<NAMES<<<<<<<<<<<<<<<<<<
    // MRZ line 2: A12345671IND8001011M2501015<<<<<<<<<<<<<<06
    //             [passport no][check][country][YYMMDD][check][sex][YYMMDD][check]...
    final mrzLine1Pattern = RegExp(r'^P<([A-Z]{3})<(.+)$');
    final mrzLine2Pattern = RegExp(r'^([A-Z]\d{7})\d([A-Z]{3})(\d{6})\d([MF<])(\d{6})\d');

    String? mrzLine1;
    String? mrzLine2;

    for (final line in lines) {
      final cleaned = line.replaceAll(' ', '').toUpperCase();
      if (mrzLine1 == null && mrzLine1Pattern.hasMatch(cleaned)) {
        mrzLine1 = cleaned;
      } else if (mrzLine2 == null && mrzLine2Pattern.hasMatch(cleaned)) {
        mrzLine2 = cleaned;
      }
    }

    if (mrzLine1 != null && mrzLine2 != null) {
      // Parse MRZ line 1: names
      final m1 = mrzLine1Pattern.firstMatch(mrzLine1)!;
      nationality = m1.group(1); // e.g., IND
      final namePart = m1.group(2)!;
      final nameSplit = namePart.split('<<');
      if (nameSplit.isNotEmpty) {
        surname = nameSplit[0].replaceAll('<', ' ').trim();
      }
      if (nameSplit.length > 1) {
        name = nameSplit[1].replaceAll('<', ' ').trim();
      }

      // Parse MRZ line 2: passport number, DOB, gender, expiry
      final m2 = mrzLine2Pattern.firstMatch(mrzLine2)!;
      passportNumber = m2.group(1);
      // nationality from line 2 if not from line 1
      nationality ??= m2.group(2);
      // DOB: YYMMDD → DD/MM/YYYY
      final dobYYMMDD = m2.group(3)!;
      dob = _mrzDateToDisplay(dobYYMMDD);
      // Gender
      final genderChar = m2.group(4)!;
      if (genderChar == 'M') gender = 'Male';
      if (genderChar == 'F') gender = 'Female';
      // Expiry: YYMMDD
      final expiryYYMMDD = m2.group(5)!;
      dateOfExpiry = _mrzDateToDisplay(expiryYYMMDD);
    }

    // ── Labeled field parsing (old booklet + supplement for new format) ──────
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // Passport number (if not from MRZ)
      if (passportNumber == null) {
        final match = passportNumPattern.firstMatch(line);
        if (match != null) {
          passportNumber = match.group(1);
          continue;
        }
      }

      // Surname
      if (upper.contains('SURNAME') || upper.contains('SUR NAME')) {
        surname ??= _extractValue(line, lines, i);
        continue;
      }

      // Given name
      if (upper.contains('GIVEN NAME') || upper.contains('GIVEN NAMES')) {
        name ??= _extractValue(line, lines, i);
        continue;
      }

      // Name (generic — old format)
      if (upper.contains('NAME') &&
          !upper.contains('SUR') &&
          !upper.contains('GIVEN') &&
          !upper.contains('FATHER') &&
          name == null) {
        name = _extractValue(line, lines, i);
        continue;
      }

      // Nationality
      if (upper.contains('NATIONALITY')) {
        nationality ??= _extractValue(line, lines, i) ?? 'INDIAN';
        continue;
      }

      // Gender / Sex
      if (upper.contains('SEX') || upper.contains('GENDER')) {
        if (gender == null) {
          final match = genderPattern.firstMatch(line);
          if (match != null) {
            final g = match.group(1)!.toUpperCase();
            gender = (g == 'M' || g == 'MALE') ? 'Male' : 'Female';
          }
        }
        continue;
      }

      // Date of Birth
      if ((upper.contains('BIRTH') || upper.contains('DOB')) &&
          !upper.contains('PLACE')) {
        if (dob == null) {
          final match = datePattern.firstMatch(line);
          if (match != null) dob = match.group(1);
        }
        continue;
      }

      // Place of Birth
      if (upper.contains('PLACE OF BIRTH') || upper.contains('PLACE/CITY OF BIRTH')) {
        placeOfBirth ??= _extractValue(line, lines, i);
        continue;
      }

      // Date of Issue
      if (upper.contains('ISSUE') && !upper.contains('PLACE')) {
        if (dateOfIssue == null) {
          final match = datePattern.firstMatch(line);
          if (match != null) dateOfIssue = match.group(1);
        }
        continue;
      }

      // Date of Expiry
      if (upper.contains('EXPIRY') || upper.contains('EXPIRATION') || upper.contains('VALID UNTIL')) {
        if (dateOfExpiry == null) {
          final match = datePattern.firstMatch(line);
          if (match != null) dateOfExpiry = match.group(1);
        }
        continue;
      }

      // Place of Issue
      if (upper.contains('PLACE OF ISSUE') || upper.contains('ISSUED AT')) {
        placeOfIssue ??= _extractValue(line, lines, i);
        continue;
      }

      // Father name
      if (upper.contains('FATHER') || upper.contains("FATHER'S")) {
        fatherName ??= _extractValue(line, lines, i);
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

  /// Converts MRZ date YYMMDD to DD/MM/YYYY.
  /// Years 00-30 → 2000-2030, 31-99 → 1931-1999.
  static String _mrzDateToDisplay(String yymmdd) {
    if (yymmdd.length != 6) return yymmdd;
    final yy = int.tryParse(yymmdd.substring(0, 2)) ?? 0;
    final mm = yymmdd.substring(2, 4);
    final dd = yymmdd.substring(4, 6);
    final yyyy = yy <= 30 ? 2000 + yy : 1900 + yy;
    return '$dd/$mm/$yyyy';
  }

  static String? _extractValue(String line, List<String> lines, int i) {
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
