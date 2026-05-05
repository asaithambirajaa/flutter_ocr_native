/// Validates Indian document numbers — Aadhaar and PAN.
class DocumentNumberValidator {
  /// Validates an Aadhaar number and returns an error message.
  /// Returns null if valid.
  static String? validateAadhaar(String number) {
    final digits = number.replaceAll(RegExp(r'[\s\-]'), '');
    if (digits.isEmpty) return 'Aadhaar number not found';
    if (digits.length != 12) return 'Aadhaar must be 12 digits (found ${digits.length})';
    if (!RegExp(r'^\d{12}$').hasMatch(digits)) return 'Aadhaar must contain only digits';
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
    if (!RegExp(r'^[A-Z]{3}').hasMatch(p)) return 'PAN first 3 characters must be letters';
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ]').hasMatch(p)) return 'PAN 4th character is invalid holder type';
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]').hasMatch(p)) return 'PAN 5th character must be a letter';
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}').hasMatch(p)) return 'PAN characters 6-9 must be digits';
    if (!RegExp(r'^[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]$').hasMatch(p)) return 'PAN 10th character must be a letter';
    return null;
  }

  /// Returns true if valid Aadhaar.
  static bool isValidAadhaar(String number) => validateAadhaar(number) == null;

  /// Returns true if valid PAN.
  static bool isValidPAN(String pan) => validatePAN(pan) == null;

  /// Returns the holder type from a PAN number.
  /// Returns null if PAN is invalid.
  static String? panHolderType(String pan) {
    if (!isValidPAN(pan)) return null;
    switch (pan.toUpperCase()[3]) {
      case 'P': return 'Individual';
      case 'C': return 'Company';
      case 'H': return 'HUF';
      case 'F': return 'Firm';
      case 'A': return 'AOP';
      case 'T': return 'Trust';
      case 'B': return 'BOI';
      case 'L': return 'Local Authority';
      case 'J': return 'Artificial Juridical Person';
      case 'G': return 'Government';
      default: return null;
    }
  }

  /// Extracts and validates Aadhaar number from text.
  /// Returns the valid Aadhaar number or null if not found/invalid.
  static String? extractAadhaar(String text) {
    final match = RegExp(r'(?<!\d)(\d{4})[\s\-]+(\d{4})[\s\-]+(\d{4})(?!\d)').firstMatch(text);
    if (match == null) return null;
    final number = '${match.group(1)}${match.group(2)}${match.group(3)}';
    return isValidAadhaar(number) ? match.group(0) : null;
  }

  /// Extracts and validates PAN number from text.
  /// Returns the valid PAN or null if not found/invalid.
  static String? extractPAN(String text) {
    final match = RegExp(r'[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]').firstMatch(text.toUpperCase());
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
