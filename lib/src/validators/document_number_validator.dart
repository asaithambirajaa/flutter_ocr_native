/// Validates Indian document numbers — Aadhaar and PAN.
class DocumentNumberValidator {
  /// Validates an Aadhaar number and returns an error message.
  /// Returns null if valid.
  static String? validateAadhaar(String number) {
    final digits = number.replaceAll(RegExp(r'[\s\-]'), '');
    if (digits.isEmpty) return 'Aadhaar number not found';
    if (digits.length != 12) {
      return 'Aadhaar must be 12 digits (found ${digits.length})';
    }
    if (!RegExp(r'^\d{12}$').hasMatch(digits)) {
      return 'Aadhaar must contain only digits';
    }
    if (digits[0] == '0') return 'Aadhaar cannot start with 0';
    if (digits[0] == '1') return 'Aadhaar cannot start with 1';
    if (!_verhoeffCheck(digits)) return 'Aadhaar checksum invalid';
    return null;
  }

  /// Validates a PAN number and returns an error message.
  /// Returns null if valid.
  static String? validatePAN(String pan) {
    final p = pan.trim().toUpperCase();
    if (p.isEmpty) return 'PAN number not found';
    if (p.length != 10) return 'PAN must be 10 characters (found ${p.length})';
    if (!RegExp(r'^[A-Z]{3}').hasMatch(p)) {
      return 'PAN first 3 characters must be letters';
    }
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ]').hasMatch(p)) {
      return 'PAN 4th character is invalid holder type';
    }
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]').hasMatch(p)) {
      return 'PAN 5th character must be a letter';
    }
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}').hasMatch(p)) {
      return 'PAN characters 6-9 must be digits';
    }
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]$').hasMatch(p)) {
      return 'PAN 10th character must be a letter';
    }
    return null;
  }

  /// Returns true if valid Aadhaar.
  static bool isValidAadhaar(String number) => validateAadhaar(number) == null;

  /// Returns true if valid PAN.
  static bool isValidPAN(String pan) => validatePAN(pan) == null;

  /// Validates an IFSC code and returns an error message.
  /// Format: 4 letters + 0 + 6 alphanumeric (e.g., SBIN0001234)
  /// Returns null if valid.
  static String? validateIFSC(String ifsc) {
    final code = ifsc.trim().toUpperCase();
    if (code.isEmpty) return 'IFSC code not found';
    if (code.length != 11) {
      return 'IFSC must be 11 characters (found ${code.length})';
    }
    if (!RegExp(r'^[A-Z]{4}').hasMatch(code)) {
      return 'IFSC first 4 characters must be letters';
    }
    if (code[4] != '0') return 'IFSC 5th character must be 0';
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(code)) {
      return 'IFSC last 6 characters must be alphanumeric';
    }
    return null;
  }

  /// Returns true if valid IFSC.
  static bool isValidIFSC(String ifsc) => validateIFSC(ifsc) == null;

  /// Validates a bank account number and returns an error message.
  /// Indian bank accounts are 9-18 digits.
  /// Returns null if valid.
  static String? validateAccountNumber(String number) {
    final digits = number.replaceAll(RegExp(r'[\s\-]'), '');
    if (digits.isEmpty) return 'Account number not found';
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Account number must contain only digits';
    }
    if (digits.length < 9) return 'Account number too short (minimum 9 digits)';
    if (digits.length > 18) {
      return 'Account number too long (maximum 18 digits)';
    }
    return null;
  }

  /// Returns true if valid account number.
  static bool isValidAccountNumber(String number) =>
      validateAccountNumber(number) == null;

  /// Extracts IFSC code from text.
  static String? extractIFSC(String text) {
    final match =
        RegExp(r'\b([A-Z]{4}0[A-Z0-9]{6})\b').firstMatch(text.toUpperCase());
    return match != null && isValidIFSC(match.group(1)!)
        ? match.group(1)
        : null;
  }

  /// Validates an Indian passport number.
  /// Format: 1 uppercase letter + 7 digits (e.g., J8369854)
  static String? validatePassport(String number) {
    final p = number.trim().toUpperCase();
    if (p.isEmpty) return 'Passport number not found';
    if (p.length != 8) {
      return 'Passport must be 8 characters (found ${p.length})';
    }
    if (!RegExp(r'^[A-Z]').hasMatch(p)) {
      return 'Passport must start with a letter';
    }
    if (!RegExp(r'^[A-Z]\d{7}$').hasMatch(p)) {
      return 'Passport must have 1 letter followed by 7 digits';
    }
    return null;
  }

  /// Returns true if valid passport number.
  static bool isValidPassport(String number) =>
      validatePassport(number) == null;

  /// Extracts passport number from text.
  static String? extractPassport(String text) {
    final match = RegExp(r'\b([A-Z]\d{7})\b').firstMatch(text.toUpperCase());
    return match != null && isValidPassport(match.group(1)!)
        ? match.group(1)
        : null;
  }

  /// Validates an Indian driving license number.
  /// Format: 2 letters (state) + 2 digits (RTO) + 4 digits (year) + 7 digits (serial)
  /// e.g., DL0420110149646, TN0120190012345
  static String? validateDrivingLicense(String number) {
    final dl = number.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (dl.isEmpty) return 'DL number not found';
    if (dl.length != 15 && dl.length != 16) {
      return 'DL must be 15-16 characters (found ${dl.length})';
    }
    if (!RegExp(r'^[A-Z]{2}').hasMatch(dl)) {
      return 'DL must start with 2-letter state code';
    }
    if (!RegExp(r'^[A-Z]{2}\d{13,14}$').hasMatch(dl)) return 'DL format invalid';
    return null;
  }

  /// Returns true if valid DL number.
  static bool isValidDrivingLicense(String number) =>
      validateDrivingLicense(number) == null;

  /// Extracts DL number from text.
  static String? extractDrivingLicense(String text) {
    final match = RegExp(r'\b([A-Z]{2}[\-\s]?\d{2}[\-\s]?\d{4}[\-\s]?\d{7})\b')
        .firstMatch(text.toUpperCase());
    if (match == null) return null;
    final dl = match.group(0)!.replaceAll(RegExp(r'[\s\-]'), '');
    return isValidDrivingLicense(dl) ? dl : null;
  }

  /// Validates an Indian Voter ID (EPIC) number.
  /// Format: 3 uppercase letters + 6-7 digits (e.g., ABC123456 or ABC1234567)
  static String? validateVoterId(String number) {
    final epic = number.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (epic.isEmpty) return 'Voter ID number not found';
    if (epic.length != 9 && epic.length != 10) {
      return 'Voter ID must be 9-10 characters (found ${epic.length})';
    }
    if (!RegExp(r'^[A-Z]{3}').hasMatch(epic)) {
      return 'Voter ID must start with 3 letters';
    }
    if (!RegExp(r'^[A-Z]{3}\d{6,7}$').hasMatch(epic)) {
      return 'Voter ID must have 3 letters followed by 6-7 digits';
    }
    return null;
  }

  /// Returns true if valid Voter ID.
  static bool isValidVoterId(String number) => validateVoterId(number) == null;

  /// Extracts Voter ID (EPIC) number from text.
  static String? extractVoterId(String text) {
    if (text.isEmpty) return null;

    final upper = text.toUpperCase();

    // Remove common punctuation but keep spaces and newlines for structure
    final cleaned = upper.replaceAll(RegExp(r'[^A-Z0-9\s\n]'), ' ');

    // Try multiple extraction strategies

    // Strategy 1: Look for standard EPIC pattern (9 or 10 chars) with word boundaries
    final epicPattern = RegExp(r'\b([A-Z]{3}\d{6,7})\b');
    final matches = epicPattern.allMatches(cleaned);

    for (final match in matches) {
      final candidate = match.group(1)!;
      if (_isValidEpicCandidate(candidate)) {
        return candidate;
      }
    }

    // Strategy 2: Handle missing first letter - look for 2 letters + 6-7 digits
    final missingFirstPattern = RegExp(r'\b([A-Z]{2}\d{6,7})\b');
    final missingFirstMatches = missingFirstPattern.allMatches(cleaned);

    for (final match in missingFirstMatches) {
      final partial = match.group(1)!;
      // Try common first letters for Indian states
      final commonFirstLetters = [
        'A',
        'B',
        'C',
        'D',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'P',
        'R',
        'S',
        'T',
        'U',
        'W'
      ];

      for (final firstLetter in commonFirstLetters) {
        final candidate = '$firstLetter$partial';
        if (_isValidEpicCandidate(candidate)) {
          return candidate;
        }
      }
    }

    // Strategy 3: Look for pattern with spaces between letters and numbers
    final spacedPattern = RegExp(r'\b([A-Z]{3})\s+(\d{6,7})\b');
    final spacedMatch = spacedPattern.firstMatch(cleaned);
    if (spacedMatch != null) {
      final candidate = '${spacedMatch.group(1)}${spacedMatch.group(2)}';
      if (_isValidEpicCandidate(candidate)) {
        return candidate;
      }
    }

    // Strategy 4: Handle missing first letter with spaces
    final spacedMissingFirstPattern = RegExp(r'\b([A-Z]{2})\s+(\d{6,7})\b');
    final spacedMissingFirstMatch =
        spacedMissingFirstPattern.firstMatch(cleaned);
    if (spacedMissingFirstMatch != null) {
      final partial =
          '${spacedMissingFirstMatch.group(1)}${spacedMissingFirstMatch.group(2)}';
      final commonFirstLetters = [
        'A',
        'B',
        'C',
        'D',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'P',
        'R',
        'S',
        'T',
        'U',
        'W'
      ];

      for (final firstLetter in commonFirstLetters) {
        final candidate = '$firstLetter$partial';
        if (_isValidEpicCandidate(candidate)) {
          return candidate;
        }
      }
    }

    // Strategy 5: Look for any 3 letters followed by 6-7 digits (more permissive)
    final permissivePattern = RegExp(r'([A-Z]{3})(\d{6,7})');
    final permissiveMatches =
        permissivePattern.allMatches(cleaned.replaceAll(' ', ''));

    for (final match in permissiveMatches) {
      final candidate = '${match.group(1)}${match.group(2)}';
      if (_isValidEpicCandidate(candidate)) {
        return candidate;
      }
    }

    // Strategy 6: Handle missing first letter in permissive mode
    final permissiveMissingFirstPattern = RegExp(r'([A-Z]{2})(\d{6,7})');
    final permissiveMissingFirstMatches =
        permissiveMissingFirstPattern.allMatches(cleaned.replaceAll(' ', ''));

    for (final match in permissiveMissingFirstMatches) {
      final partial = '${match.group(1)}${match.group(2)}';
      final commonFirstLetters = [
        'I',
        'A',
        'B',
        'C',
        'D',
        'G',
        'H',
        'J',
        'K',
        'L',
        'M',
        'N',
        'P',
        'R',
        'S',
        'T',
        'U',
        'W'
      ];

      for (final firstLetter in commonFirstLetters) {
        final candidate = '$firstLetter$partial';
        if (_isValidEpicCandidate(candidate)) {
          return candidate;
        }
      }
    }

    // Strategy 7: Handle line breaks between letters and numbers
    final lines = cleaned
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    for (int i = 0; i < lines.length - 1; i++) {
      final currentLine = lines[i].trim();
      final nextLine = lines[i + 1].trim();

      // Check if current line has 1-3 letters and next line has remaining pattern
      if (RegExp(r'^[A-Z]{1,3}$').hasMatch(currentLine)) {
        final combined = currentLine + nextLine.replaceAll(' ', '');
        final match = RegExp(r'^([A-Z]{3}\d{6,7})').firstMatch(combined);
        if (match != null) {
          final candidate = match.group(1)!;
          if (_isValidEpicCandidate(candidate)) {
            return candidate;
          }
        }
      }
    }

    return null;
  }

  /// Helper method to validate if a candidate EPIC number is likely valid
  static bool _isValidEpicCandidate(String candidate) {
    if (!isValidVoterId(candidate)) return false;

    // Skip if digits look like a date
    final digits = candidate.substring(3);
    if (_looksLikeDate(digits)) return false;

    // Skip if letters are common word fragments
    final letters = candidate.substring(0, 3);
    if (_isCommonWordFragment(letters)) return false;

    return true;
  }

  /// Checks if 6-7 digits look like a date (DDMMYYYY, DDMMYY, YYYYMMDD patterns)
  static bool _looksLikeDate(String digits) {
    if (digits.length < 6) return false;
    // DDMMYY or DDMMYYY pattern (6-7 digits)
    final dd6 = int.tryParse(digits.substring(0, 2)) ?? 0;
    final mm6 = int.tryParse(digits.substring(2, 4)) ?? 0;
    if (dd6 >= 1 && dd6 <= 31 && mm6 >= 1 && mm6 <= 12) {
      // Check if remaining digits look like a year
      final yearPart = digits.substring(4);
      final year = int.tryParse(yearPart) ?? 0;
      if (yearPart.length == 2 && year >= 0 && year <= 99) return true;
      if (yearPart.length == 3 && year >= 190 && year <= 209) return true;
      if (yearPart.length == 4 && year >= 1900 && year <= 2099) return true;
    }
    // YYYYMMDD (8 digits)
    if (digits.length >= 8) {
      final yyyy = int.tryParse(digits.substring(0, 4)) ?? 0;
      final mm = int.tryParse(digits.substring(4, 6)) ?? 0;
      final dd = int.tryParse(digits.substring(6, 8)) ?? 0;
      if (yyyy >= 1900 && yyyy <= 2099 && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31) {
        return true;
      }
    }
    return false;
  }

  /// Checks if 3 letters are a common word fragment (not a state code)
  static bool _isCommonWordFragment(String letters) {
    const fragments = [
      'DOB', 'ADD', 'AGE', 'SEX', 'PIN', 'RTH', 'THE', 'AND', 'FOR', 'NOT',
      'GOV', 'UID', 'VID', 'YOB', 'REF', 'MOB', 'TEL', 'FAX',
      // Bank abbreviations that appear on documents
      'IOB', 'SBI', 'PNB', 'BOI', 'BOB', 'UCO', 'OBC', 'CBI',
    ];
    return fragments.contains(letters);
  }

  /// Returns the holder type from a PAN number.
  /// Returns null if PAN is invalid.
  static String? panHolderType(String pan) {
    if (!isValidPAN(pan)) return null;
    switch (pan.toUpperCase()[3]) {
      case 'P':
        return 'Individual';
      case 'C':
        return 'Company';
      case 'H':
        return 'HUF';
      case 'F':
        return 'Firm';
      case 'A':
        return 'AOP';
      case 'T':
        return 'Trust';
      case 'B':
        return 'BOI';
      case 'L':
        return 'Local Authority';
      case 'J':
        return 'Artificial Juridical Person';
      case 'G':
        return 'Government';
      default:
        return null;
    }
  }

  /// Extracts and validates Aadhaar number from text.
  /// Returns the valid Aadhaar number or null if not found/invalid.
  static String? extractAadhaar(String text) {
    // Try with separators first (e.g., "5689 2365 8955")
    final match = RegExp(r'(?<!\d)(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})(?!\d)')
        .firstMatch(text);
    if (match != null) {
      final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
      if (isValidAadhaar(number)) return match.group(0);
    }
    // Try with optional/partial separators (e.g., "5689 23658955", "568923658955")
    final permissive = RegExp(r'(?<!\d)(\d{4})[\s\-]*(\d{4})[\s\-]*(\d{4})(?!\d)')
        .firstMatch(text);
    if (permissive != null) {
      final number = '${permissive.group(1)}${permissive.group(2)}${permissive.group(3)}';
      if (isValidAadhaar(number)) return permissive.group(0);
    }
    // Try without separators (e.g., "568923658955")
    final noSepMatch = RegExp(r'(?<!\d)(\d{12})(?!\d)').firstMatch(text);
    if (noSepMatch != null) {
      final number = noSepMatch.group(1)!;
      if (isValidAadhaar(number)) return number;
    }
    return null;
  }

  /// Extracts and validates PAN number from text.
  /// Returns the valid PAN or null if not found/invalid.
  static String? extractPAN(String text) {
    final match = RegExp(r'[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]')
        .firstMatch(text.toUpperCase());
    if (match == null) return null;
    return isValidPAN(match.group(0)!) ? match.group(0) : null;
  }

  // --- Verhoeff Algorithm ---

  static const _verhoeffD = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
  ];

  static const _verhoeffP = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
    [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
  ];

  /// Verhoeff checksum validation.
  /// Returns true if the number passes the Verhoeff check.
  static bool _verhoeffCheck(String number) {
    int c = 0;
    final reversed = number.split('').reversed.toList();
    for (int i = 0; i < reversed.length; i++) {
      final digit = int.parse(reversed[i]);
      c = _verhoeffD[c][_verhoeffP[i % 8][digit]];
    }
    return c == 0;
  }
}
