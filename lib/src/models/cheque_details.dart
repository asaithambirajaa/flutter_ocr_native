/// Parsed cheque details extracted from OCR text.
/// Supports both old handwritten-style cheques and new CTS printed cheques
/// (A/C No. label, MICR band, printed IFSC).
class ChequeDetails {
  final String? payeeName;
  final String? amountInWords;
  final String? amountInFigures;
  final String? date;
  final String? accountNumber;
  final String? ifscCode;
  final String? bankName;
  final String? chequeNumber;
  final String? branchName;
  final String? address;
  final String rawText;

  const ChequeDetails({
    this.payeeName,
    this.amountInWords,
    this.amountInFigures,
    this.date,
    this.accountNumber,
    this.ifscCode,
    this.bankName,
    this.chequeNumber,
    this.branchName,
    this.address,
    required this.rawText,
  });

  /// Parses OCR text from a cheque into structured fields.
  /// Handles:
  /// - Old format: handwritten Pay/Payee, Rupees label, 6-digit cheque number
  /// - New CTS format: printed A/C No., IFSC label, MICR band, Account No. label
  factory ChequeDetails.fromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? payeeName;
    String? amountInWords;
    String? amountInFigures;
    String? date;
    String? accountNumber;
    String? ifscCode;
    String? bankName;
    String? chequeNumber;
    String? branchName;
    String? address;

    final ifscPattern = RegExp(r'\b([A-Za-z]{4}0[A-Za-z0-9]{6})\b');
    final accountPattern = RegExp(r'\b(\d[\d\s]{8,20}\d)\b');
    final accountCleanPattern = RegExp(r'\b(\d{9,18})\b');
    // A/C No., Account No., Acc No., Account Number, A/C Number
    final accountLabelPattern = RegExp(
      r'(A\s*/\s*C|ACC(OUNT)?|ACCOUNT)\s*(NO\.?|NUMBER|#)?\s*[:\.]?\s*',
      caseSensitive: false,
    );
    final datePattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{2,4})');
    final amountFigurePattern = RegExp(r'[₹Rs.]*\s*(\d[\d,]*\.?\d*)');
    final chequeNumPattern = RegExp(r'\b(\d{6})\b');
    final payLabelPattern = RegExp(r'(Pay\s*(to)?|Payee)[:\s]*', caseSensitive: false);
    final amountLabelPattern = RegExp(r'(Rupees|Amount|Rs\.?)[:\s]*', caseSensitive: false);

    final bankPatterns = [
      RegExp(r'State\s*Bank\s*(of\s*India)?', caseSensitive: false),
      RegExp(r'\bSBI\b', caseSensitive: false),
      RegExp(r'\bHDFC\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'\bICICI\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'\bAxis\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'\bKotak\s*(Mahindra)?\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'Punjab\s*National\s*Bank|\bPNB\b', caseSensitive: false),
      RegExp(r'Bank\s*of\s*Baroda|\bBOB\b', caseSensitive: false),
      RegExp(r'Union\s*Bank\s*(of\s*India)?', caseSensitive: false),
      RegExp(r'Canara\s*Bank', caseSensitive: false),
      RegExp(r'Indian\s*Bank', caseSensitive: false),
      RegExp(r'Bank\s*of\s*India|\bBOI\b', caseSensitive: false),
      RegExp(r'\bIndusInd\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'\bYes\s*Bank\b', caseSensitive: false),
      RegExp(r'Federal\s*Bank', caseSensitive: false),
      RegExp(r'\bIDBI\s*(Bank)?\b', caseSensitive: false),
      RegExp(r'\bUCO\s*Bank\b', caseSensitive: false),
      RegExp(r'Central\s*Bank\s*(of\s*India)?', caseSensitive: false),
      RegExp(r'\bIOB\b|Indian\s*Overseas\s*Bank', caseSensitive: false),
      RegExp(r'South\s*Indian\s*Bank', caseSensitive: false),
      RegExp(r'Karnataka\s*Bank', caseSensitive: false),
      RegExp(r'Bandhan\s*Bank', caseSensitive: false),
      RegExp(r'IDFC\s*(First)?\s*(Bank)?', caseSensitive: false),
      RegExp(r'RBL\s*Bank|Ratnakar', caseSensitive: false),
      RegExp(r'Jammu\s*(&|and)\s*Kashmir\s*Bank|\bJ&K\s*Bank\b', caseSensitive: false),
      RegExp(r'City\s*Union\s*Bank', caseSensitive: false),
      RegExp(r'Karur\s*Vysya\s*Bank|\bKVB\b', caseSensitive: false),
      RegExp(r'Tamilnad\s*Mercantile\s*Bank|\bTMB\b', caseSensitive: false),
      RegExp(r'DCB\s*Bank', caseSensitive: false),
      RegExp(r'Dhanlaxmi\s*Bank', caseSensitive: false),
      RegExp(r'Lakshmi\s*Vilas\s*Bank', caseSensitive: false),
      RegExp(r'Co[\-\s]*operative\s*(Bank)?', caseSensitive: false),
      RegExp(r'\bBank\b.*\bLtd\b|\bLtd\b.*\bBank\b', caseSensitive: false),
    ];

    final branchPattern = RegExp(r'(Branch|Br\.?)[:\s]*(.+)', caseSensitive: false);
    final addressIndicators = RegExp(
      r'(Road|Rd|Street|St|Nagar|Colony|Layout|Cross|Main|Floor|'
      r'Block|Sector|Phase|Plot|Near|Opp|Behind|Market|Circle|'
      r'District|Dist|Taluk|Pin|Post|P\.?O|City|Town|\d{6})',
      caseSensitive: false,
    );

    final consumed = <int>{};
    final addressLines = <String>[];

    // First pass: extract key fields
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // IFSC code
      if (ifscCode == null) {
        final ifscMatch = ifscPattern.firstMatch(line);
        if (ifscMatch != null) {
          ifscCode = ifscMatch.group(1)!.toUpperCase();
          consumed.add(i);
          continue;
        }
        if (upper.contains('IFSC')) {
          final codeMatch = RegExp(r'[A-Za-z]{4}0[A-Za-z0-9]{6}').firstMatch(line);
          if (codeMatch != null) {
            ifscCode = codeMatch.group(0)!.toUpperCase();
            consumed.add(i);
            continue;
          }
          // IFSC label but code on next line
          if (i + 1 < lines.length) {
            final nextMatch = ifscPattern.firstMatch(lines[i + 1]);
            if (nextMatch != null) {
              ifscCode = nextMatch.group(1)!.toUpperCase();
              consumed.add(i);
              consumed.add(i + 1);
              continue;
            }
          }
        }
      }

      // Account number — labeled (new CTS format: "A/C No.", "Account No.", etc.)
      if (accountNumber == null && accountLabelPattern.hasMatch(line)) {
        final afterLabel = line.replaceAll(accountLabelPattern, '').trim();
        final accMatch = RegExp(r'(\d[\d\s]{7,19}\d)').firstMatch(afterLabel);
        if (accMatch != null) {
          final cleaned = accMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
          if (cleaned.length >= 9 && cleaned.length <= 18) {
            accountNumber = cleaned;
            consumed.add(i);
            continue;
          }
        }
        // Value on next line
        if (i + 1 < lines.length) {
          final nextMatch = RegExp(r'(\d{9,18})').firstMatch(lines[i + 1]);
          if (nextMatch != null) {
            accountNumber = nextMatch.group(1);
            consumed.add(i);
            consumed.add(i + 1);
            continue;
          }
        }
      }

      // Date
      if (date == null) {
        final dateMatch = datePattern.firstMatch(line);
        if (dateMatch != null) {
          date = dateMatch.group(1);
          consumed.add(i);
          continue;
        }
      }

      // Bank name
      if (bankName == null) {
        for (final pattern in bankPatterns) {
          if (pattern.hasMatch(line)) {
            bankName = line;
            consumed.add(i);
            break;
          }
        }
        if (bankName != null) continue;
      }

      // Branch
      if (branchName == null) {
        final branchMatch = branchPattern.firstMatch(line);
        if (branchMatch != null) {
          branchName = branchMatch.group(2)?.trim();
          consumed.add(i);
          continue;
        }
      }

      // Pay to / Payee
      if (payeeName == null && payLabelPattern.hasMatch(line)) {
        payeeName = line.replaceAll(payLabelPattern, '').trim();
        if (payeeName.isEmpty && i + 1 < lines.length) {
          payeeName = lines[i + 1];
          consumed.add(i + 1);
        }
        consumed.add(i);
        continue;
      }

      // Amount in words
      if (amountInWords == null && amountLabelPattern.hasMatch(line)) {
        amountInWords = line.replaceAll(amountLabelPattern, '').trim();
        consumed.add(i);
        continue;
      }
    }

    // Second pass: account number (unlabeled), cheque number, amount, address
    for (int i = 0; i < lines.length; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];

      // Account number — spaced format then clean digits
      if (accountNumber == null) {
        final spacedMatch = accountPattern.firstMatch(line);
        if (spacedMatch != null) {
          final cleaned = spacedMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
          if (cleaned.length >= 9 && cleaned.length <= 18) {
            if (!(cleaned.length == 10 && RegExp(r'^[6-9]').hasMatch(cleaned))) {
              accountNumber = cleaned;
              consumed.add(i);
              continue;
            }
          }
        }
        final cleanMatch = accountCleanPattern.firstMatch(line);
        if (cleanMatch != null) {
          final num = cleanMatch.group(1)!;
          if (num.length >= 9) {
            if (!(num.length == 10 && RegExp(r'^[6-9]').hasMatch(num))) {
              accountNumber = num;
              consumed.add(i);
              continue;
            }
          }
        }
      }

      // Cheque number (6 digits, mostly numeric line — MICR area)
      if (chequeNumber == null) {
        final chequeMatch = chequeNumPattern.firstMatch(line);
        if (chequeMatch != null) {
          final num = chequeMatch.group(1)!;
          if (line.replaceAll(RegExp(r'[\s\d]'), '').length < 5) {
            chequeNumber = num;
            consumed.add(i);
            continue;
          }
        }
      }

      // Amount in figures
      if (amountInFigures == null && line.contains(RegExp(r'[₹$]|Rs'))) {
        final figMatch = amountFigurePattern.firstMatch(line);
        if (figMatch != null) {
          amountInFigures = figMatch.group(1);
          consumed.add(i);
          continue;
        }
      }

      // Address lines
      if (addressIndicators.hasMatch(line)) {
        addressLines.add(line);
        consumed.add(i);
      }
    }

    if (addressLines.isNotEmpty) {
      address = addressLines.join(', ');
    }

    // Fallback: extract account number from text near IFSC
    if (accountNumber == null && ifscCode != null) {
      final fullText = text.replaceAll(RegExp(r'\s+'), ' ');
      final parts = fullText.split(RegExp(ifscCode, caseSensitive: false));
      if (parts.length > 1) {
        final accMatch = RegExp(r'(\d{9,18})').firstMatch(parts.last);
        if (accMatch != null) accountNumber = accMatch.group(1);
      }
    }

    // Fallback: bank name from any line with "Bank"
    if (bankName == null) {
      for (int i = 0; i < lines.length; i++) {
        if (consumed.contains(i)) continue;
        final line = lines[i];
        if (RegExp(r'\bBank\b', caseSensitive: false).hasMatch(line) && line.length > 5) {
          bankName = line;
          break;
        }
      }
    }

    return ChequeDetails(
      payeeName: payeeName,
      amountInWords: amountInWords,
      amountInFigures: amountInFigures,
      date: date,
      accountNumber: accountNumber,
      ifscCode: ifscCode,
      bankName: bankName,
      chequeNumber: chequeNumber,
      branchName: branchName,
      address: address,
      rawText: text,
    );
  }

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (bankName != null) map['Bank'] = bankName!;
    if (branchName != null) map['Branch'] = branchName!;
    if (address != null) map['Address'] = address!;
    if (ifscCode != null) map['IFSC'] = ifscCode!;
    if (accountNumber != null) map['Account No.'] = accountNumber!;
    if (chequeNumber != null) map['Cheque No.'] = chequeNumber!;
    if (payeeName != null) map['Pay To'] = payeeName!;
    if (date != null) map['Date'] = date!;
    if (amountInFigures != null) map['Amount'] = '₹$amountInFigures';
    if (amountInWords != null) map['Amount (Words)'] = amountInWords!;
    return map;
  }
}
