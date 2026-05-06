import 'package:flutter/material.dart';

import 'document_number_validator.dart';

/// Detected document types.
enum DetectedDocType {
  aadhaar,
  pan,
  passport,
  drivingLicense,
  voterId,
  cheque,
  unknown,
}

/// Auto-detects document type from OCR text.
class DocumentTypeDetector {
  /// Detects the document type from OCR text.
  /// Analyzes keywords and number patterns to determine the document.
  static DetectedDocType detect(String text) {
    final upper = text.toUpperCase();

    // Score each type
    final scores = <DetectedDocType, int>{};

    // Aadhaar
    scores[DetectedDocType.aadhaar] = _scoreAadhaar(upper, text);

    // PAN
    scores[DetectedDocType.pan] = _scorePan(upper, text);

    // Passport
    scores[DetectedDocType.passport] = _scorePassport(upper, text);

    // Driving License
    scores[DetectedDocType.drivingLicense] = _scoreDL(upper, text);

    // Voter ID
    scores[DetectedDocType.voterId] = _scoreVoterId(upper, text);

    // Cheque
    scores[DetectedDocType.cheque] = _scoreCheque(upper, text);

    // Pick highest score
    final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return best.value > 0 ? best.key : DetectedDocType.unknown;
  }

  static int _scoreAadhaar(String upper, String text) {
    int score = 0;
    if (upper.contains('AADHAAR') || upper.contains('UIDAI')) score += 5;
    if (upper.contains('UNIQUE IDENTIFICATION')) score += 5;
    // 12-digit pattern (unmasked)
    if (RegExp(r'(?<!\d)\d{4}[\s\-]+\d{4}[\s\-]+\d{4}(?!\d)').hasMatch(text)) score += 4;
    // Masked pattern XXXX XXXX 1234
    if (RegExp(r'XXXX[\s\-]+XXXX[\s\-]+\d{4}').hasMatch(text)) score += 4;
    if (DocumentNumberValidator.extractAadhaar(text) != null) score += 3;
    // Generic fields boost only if some Aadhaar signal exists
    if (score > 0) {
      if (upper.contains('GOVERNMENT OF INDIA')) score += 1;
      if (upper.contains('DOB') || upper.contains('DATE OF BIRTH')) score += 1;
      if (upper.contains('S/O') || upper.contains('D/O') || upper.contains('W/O')) score += 1;
    }
    // DOB + 12 digits without keyword is still likely Aadhaar
    if (score == 0 && (upper.contains('DOB') || upper.contains('MALE') || upper.contains('FEMALE'))) {
      if (RegExp(r'(?<!\d)\d{4}[\s\-]+\d{4}[\s\-]+\d{4}(?!\d)').hasMatch(text) ||
          RegExp(r'XXXX[\s\-]+XXXX[\s\-]+\d{4}').hasMatch(text)) {
        score += 3;
      }
    }
    return score;
  }

  static int _scorePan(String upper, String text) {
    int score = 0;
    if (upper.contains('INCOME TAX')) score += 3;
    if (upper.contains('PERMANENT ACCOUNT')) score += 3;
    if (upper.contains('PAN')) score += 1;
    if (RegExp(r'[A-Z]{3}[CPFHATBLGJ][A-Z]\d{4}[A-Z]').hasMatch(text.toUpperCase())) score += 3;
    if (DocumentNumberValidator.extractPAN(text) != null) score += 2;
    return score;
  }

  static int _scorePassport(String upper, String text) {
    int score = 0;
    if (upper.contains('PASSPORT')) score += 3;
    if (upper.contains('REPUBLIC OF INDIA')) score += 2;
    if (upper.contains('NATIONALITY')) score += 2;
    if (upper.contains('SURNAME')) score += 2;
    if (upper.contains('GIVEN NAME')) score += 2;
    if (upper.contains('PLACE OF BIRTH')) score += 2;
    if (upper.contains('DATE OF EXPIRY') || upper.contains('EXPIRY')) score += 1;
    if (upper.contains('PLACE OF ISSUE')) score += 1;
    if (RegExp(r'\b[A-Z]\d{7}\b').hasMatch(text.toUpperCase())) score += 2;
    if (DocumentNumberValidator.extractPassport(text) != null) score += 2;
    return score;
  }

  static int _scoreDL(String upper, String text) {
    int score = 0;
    if (upper.contains('DRIVING') || upper.contains('LICENCE') || upper.contains('LICENSE')) score += 3;
    if (upper.contains('TRANSPORT')) score += 2;
    if (upper.contains('NON-TRANSPORT') || upper.contains('NON TRANSPORT')) score += 2;
    if (upper.contains('VEHICLE CLASS') || upper.contains('COV CLASS')) score += 2;
    if (upper.contains('LMV') || upper.contains('MCWG') || upper.contains('HMV')) score += 2;
    if (upper.contains('BLOOD GROUP')) score += 1;
    if (upper.contains('RTO')) score += 2;
    if (RegExp(r'[A-Z]{2}[\-\s]?\d{2}[\-\s]?\d{4}[\-\s]?\d{7}').hasMatch(text.toUpperCase())) score += 3;
    if (DocumentNumberValidator.extractDrivingLicense(text) != null) score += 2;
    return score;
  }

  static int _scoreVoterId(String upper, String text) {
    int score = 0;
    if (upper.contains('ELECTION') || upper.contains('ELECTORAL')) score += 5;
    if (upper.contains('VOTER') || upper.contains('EPIC')) score += 5;
    if (upper.contains('COMMISSION')) score += 2;
    if (upper.contains('PHOTO IDENTITY') || upper.contains('IDENTITY CARD')) score += 3;
    if (upper.contains("ELECTOR")) score += 3;
    if (RegExp(r'\b[A-Z]{3}\d{6,7}\b').hasMatch(text.toUpperCase())) score += 2;
    if (DocumentNumberValidator.extractVoterId(text) != null) score += 3;
    return score;
  }

  static int _scoreCheque(String upper, String text) {
    int score = 0;
    if (upper.contains('PAY') && (upper.contains('BEARER') || upper.contains('ORDER'))) score += 3;
    if (upper.contains('ACCOUNT') && upper.contains('PAYEE')) score += 2;
    if (upper.contains('RUPEES') || upper.contains('₹')) score += 2;
    if (upper.contains('IFSC') || RegExp(r'[A-Z]{4}0[A-Z0-9]{6}').hasMatch(text.toUpperCase())) score += 3;
    if (upper.contains('CHEQUE') || upper.contains('CHECK')) score += 3;
    if (upper.contains('MICR') || upper.contains('CTS')) score += 2;
    if (DocumentNumberValidator.extractIFSC(text) != null) score += 2;
    return score;
  }

  /// Returns a human-readable label for the document type.
  static String label(DetectedDocType type) {
    switch (type) {
      case DetectedDocType.aadhaar: return 'Aadhaar Card';
      case DetectedDocType.pan: return 'PAN Card';
      case DetectedDocType.passport: return 'Passport';
      case DetectedDocType.drivingLicense: return 'Driving License';
      case DetectedDocType.voterId: return 'Voter ID';
      case DetectedDocType.cheque: return 'Cheque';
      case DetectedDocType.unknown: return 'Unknown';
    }
  }

  /// Returns an icon for the document type.
  static IconData icon(DetectedDocType type) {
    switch (type) {
      case DetectedDocType.aadhaar: return Icons.credit_card;
      case DetectedDocType.pan: return Icons.badge;
      case DetectedDocType.passport: return Icons.flight;
      case DetectedDocType.drivingLicense: return Icons.directions_car;
      case DetectedDocType.voterId: return Icons.how_to_vote;
      case DetectedDocType.cheque: return Icons.account_balance;
      case DetectedDocType.unknown: return Icons.help_outline;
    }
  }
}
