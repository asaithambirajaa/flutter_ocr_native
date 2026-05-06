/// Parsed cheque details extracted from OCR text.
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
    required this.rawText,
  });

  /// Parses OCR text from a cheque into structured fields.
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

    final datePattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})');
    final ifscPattern = RegExp(r'\b([A-Z]{4}0[A-Z0-9]{6})\b');
    final accountPattern = RegExp(r'\b(\d{9,18})\b');
    final amountFigurePattern = RegExp(r'[₹Rs.]*\s*(\d[\d,]*\.?\d*)');
    final chequeNumPattern = RegExp(r'\b(\d{6})\b');
    final payLabelPattern = RegExp(r'(Pay|Pay to|Payee)', caseSensitive: false);
    final amountLabelPattern = RegExp(r'(Rupees|Amount|Rs)', caseSensitive: false);
    final bankPattern = RegExp(
      r'(State Bank|SBI|HDFC|ICICI|Axis|Kotak|PNB|Bank of Baroda|'
      r'Union Bank|Canara Bank|Indian Bank|Bank of India|'
      r'IndusInd|Yes Bank|Federal Bank|IDBI|UCO Bank|'
      r'Central Bank|IOB|Punjab National)',
      caseSensitive: false,
    );
    final branchPattern = RegExp(r'(Branch|Br)[:\s]*(.+)', caseSensitive: false);

    final consumed = <int>{};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // IFSC code
      final ifscMatch = ifscPattern.firstMatch(line);
      if (ifscMatch != null && ifscCode == null) {
        ifscCode = ifscMatch.group(1);
        consumed.add(i);
        continue;
      }

      // Date
      final dateMatch = datePattern.firstMatch(line);
      if (dateMatch != null && date == null) {
        date = dateMatch.group(1);
        consumed.add(i);
        continue;
      }

      // Bank name
      final bankMatch = bankPattern.firstMatch(line);
      if (bankMatch != null && bankName == null) {
        bankName = line;
        consumed.add(i);
        continue;
      }

      // Branch
      final branchMatch = branchPattern.firstMatch(line);
      if (branchMatch != null && branchName == null) {
        branchName = branchMatch.group(2)?.trim();
        consumed.add(i);
        continue;
      }

      // Pay to / Payee
      if (payLabelPattern.hasMatch(line) && payeeName == null) {
        payeeName = line
            .replaceAll(RegExp(r'(Pay to|Pay|Payee)[:\s]*', caseSensitive: false), '')
            .trim();
        if (payeeName.isEmpty && i + 1 < lines.length) {
          payeeName = lines[i + 1];
          consumed.add(i + 1);
        }
        consumed.add(i);
        continue;
      }

      // Amount in words (line containing "Rupees" or after amount label)
      if (amountLabelPattern.hasMatch(line) && amountInWords == null) {
        amountInWords = line
            .replaceAll(RegExp(r'(Rupees|Amount|Rs\.?)[:\s]*', caseSensitive: false), '')
            .trim();
        consumed.add(i);
        continue;
      }
    }

    // Second pass: find account number and cheque number from remaining lines
    for (int i = 0; i < lines.length; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];

      // Account number (9-18 consecutive digits, not already matched as something else)
      if (accountNumber == null) {
        final accMatch = accountPattern.firstMatch(line);
        if (accMatch != null) {
          final num = accMatch.group(1)!;
          // Skip if it's a 6-digit cheque number, date-like, or phone number (10 digits starting with 6-9)
          if (num.length >= 9) {
            if (num.length == 10 && RegExp(r'^[6-9]').hasMatch(num)) {
              continue; // likely a phone number
            }
            accountNumber = num;
            consumed.add(i);
            continue;
          }
        }
      }

      // Cheque number (exactly 6 digits)
      if (chequeNumber == null) {
        final chequeMatch = chequeNumPattern.firstMatch(line);
        if (chequeMatch != null) {
          final num = chequeMatch.group(1)!;
          // Only if the line is mostly this number (MICR area)
          if (line.replaceAll(RegExp(r'[\s\d]'), '').length < 5) {
            chequeNumber = num;
            consumed.add(i);
            continue;
          }
        }
      }

      // Amount in figures (₹ or Rs followed by number)
      if (amountInFigures == null) {
        final figMatch = amountFigurePattern.firstMatch(line);
        if (figMatch != null && line.contains(RegExp(r'[₹$]|Rs'))) {
          amountInFigures = figMatch.group(1);
          consumed.add(i);
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
      rawText: text,
    );
  }

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (bankName != null) map['Bank'] = bankName!;
    if (branchName != null) map['Branch'] = branchName!;
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
