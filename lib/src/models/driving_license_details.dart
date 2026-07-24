/// Parsed driving license details extracted from OCR text.
/// Supports both old format (plain English labels) and new smart card format
/// (COV, DOI, VALIDITY, NON-TRANSPORT/TRANSPORT validity dates).
class DrivingLicenseDetails {
  final String? name;
  final String? fatherName;
  final String? dob;
  final String? dlNumber;
  final String? dateOfIssue;
  final String? validity;
  final String? address;
  final String? bloodGroup;
  final String? vehicleClass;
  final String? issuingAuthority;
  final String rawText;

  const DrivingLicenseDetails({
    this.name,
    this.fatherName,
    this.dob,
    this.dlNumber,
    this.dateOfIssue,
    this.validity,
    this.address,
    this.bloodGroup,
    this.vehicleClass,
    this.issuingAuthority,
    required this.rawText,
  });

  /// Parses OCR text from a driving license into structured fields.
  /// Handles:
  /// - Old format: plain labels (Name, S/O, DOB, Address, Valid Till)
  /// - New smart card format: COV, DOI, VALIDITY, NON-TRANSPORT/TRANSPORT dates
  /// - DL numbers with hyphens, spaces, or no separators
  factory DrivingLicenseDetails.fromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? name;
    String? fatherName;
    String? dob;
    String? dlNumber;
    String? dateOfIssue;
    String? validity;
    String? bloodGroup;
    String? vehicleClass;
    String? issuingAuthority;
    final addressLines = <String>[];

    final datePattern = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})');

    // DL number patterns — covers all Indian formats:
    // DL-0420110149646, TN01 20190012345, KA01-2020-0001234, MH12 20150012345
    final dlPatterns = [
      RegExp(r'\b([A-Z]{2})[\-\s]?(\d{2})[\-\s]?(\d{4})[\-\s]?(\d{7})\b'),
      RegExp(r'\b([A-Z]{2})[\-\s]?(\d{2})[\-\s]?(\d{4})[\-\s]?(\d{6})\b'), // some states 6-digit serial
      RegExp(r'\b([A-Z]{2})(\d{13,14})\b'), // compact no-separator
    ];

    final bloodGroupPattern = RegExp(r'\b(A|B|AB|O)[+\-](ve)?\b', caseSensitive: false);
    final vehicleClassPattern = RegExp(
      r'\b(LMV[\-\s]?NT|LMV|MCWG|MC\s*EX50CC|MC50CC|HMV|HPMV|HTV|MGV|TRANS|FVG|INVCRG|ADAPTED)\b',
      caseSensitive: false,
    );

    bool inAddress = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // DL Number — try all patterns
      if (dlNumber == null) {
        bool found = false;
        for (final pattern in dlPatterns) {
          final match = pattern.firstMatch(upper);
          if (match != null) {
            dlNumber = match.group(0)!.replaceAll(RegExp(r'[\s\-]'), '');
            found = true;
            break;
          }
        }
        if (found) continue;
        // Label-based extraction (old format: "DL No: ...")
        if (upper.contains('DL NO') ||
            upper.contains('LICENCE NO') ||
            upper.contains('LICENSE NO') ||
            upper.contains('LIC NO') ||
            upper.contains('DL NUMBER')) {
          final val = _extractValue(line, lines, i);
          if (val != null) {
            dlNumber = val.replaceAll(RegExp(r'[\s\-]'), '');
          }
          continue;
        }
      }

      // Name
      if (upper.contains('NAME') &&
          !upper.contains('FATHER') &&
          !upper.contains('S/O') &&
          !upper.contains('D/O') &&
          !upper.contains('W/O') &&
          name == null) {
        name = _extractValue(line, lines, i);
        continue;
      }

      // Father/Husband name
      if (upper.contains('S/O') ||
          upper.contains('D/O') ||
          upper.contains('W/O') ||
          upper.contains('FATHER') ||
          upper.contains('HUSBAND')) {
        fatherName = line
            .replaceAll(
                RegExp(r'(S/O|D/O|W/O|Father|FATHER|Husband|HUSBAND)[:\s]*',
                    caseSensitive: false),
                '')
            .trim();
        if (fatherName.isEmpty && i + 1 < lines.length) fatherName = lines[i + 1];
        continue;
      }

      // DOB — old: "DOB:", new smart card: "DOB" on same line with date
      if (upper.contains('DOB') || upper.contains('DATE OF BIRTH') || upper.contains('BIRTH DATE')) {
        final match = datePattern.firstMatch(line);
        if (match != null) {
          dob = match.group(1);
        } else if (i + 1 < lines.length) {
          final nextMatch = datePattern.firstMatch(lines[i + 1]);
          if (nextMatch != null) dob = nextMatch.group(1);
        }
        continue;
      }

      // Date of Issue — old: "Date of Issue", new: "DOI"
      if ((upper.contains('ISSUE') || upper.contains('DOI')) &&
          !upper.contains('PLACE')) {
        final match = datePattern.firstMatch(line);
        if (match != null) {
          dateOfIssue = match.group(1);
        } else if (i + 1 < lines.length) {
          final nextMatch = datePattern.firstMatch(lines[i + 1]);
          if (nextMatch != null) dateOfIssue = nextMatch.group(1);
        }
        continue;
      }

      // Validity — old: "Valid Till", new smart card: "VALIDITY", "NON-TRANSPORT", "TRANSPORT"
      if (upper.contains('VALID') ||
          upper.contains('EXPIRY') ||
          upper.contains('NON-TRANSPORT') ||
          upper.contains('NON TRANSPORT') ||
          upper.contains('NT VALIDITY') ||
          upper.contains('TRANSPORT VALIDITY')) {
        final match = datePattern.firstMatch(line);
        if (match != null) {
          validity ??= match.group(1);
        } else if (i + 1 < lines.length) {
          final nextMatch = datePattern.firstMatch(lines[i + 1]);
          if (nextMatch != null) validity ??= nextMatch.group(1);
        }
        continue;
      }

      // COV / Vehicle Class — new smart card uses "COV" label
      if (upper.contains('COV') || upper.contains('CLASS OF VEHICLE') || upper.contains('VEHICLE CLASS')) {
        final val = _extractValue(line, lines, i);
        if (val != null && vehicleClass == null) vehicleClass = val.toUpperCase();
        continue;
      }

      // Blood Group
      final bgMatch = bloodGroupPattern.firstMatch(line);
      if (bgMatch != null && bloodGroup == null) {
        bloodGroup = bgMatch.group(0)?.toUpperCase();
        continue;
      }

      // Vehicle Class inline (e.g., "LMV, MCWG" on a line)
      final vcMatch = vehicleClassPattern.firstMatch(line);
      if (vcMatch != null && vehicleClass == null) {
        vehicleClass = vcMatch.group(0)?.toUpperCase();
        continue;
      }

      // Address
      if (upper.contains('ADDRESS') || upper.contains('ADD:') || upper.contains('ADDR')) {
        inAddress = true;
        final val = line
            .replaceAll(RegExp(r'(Address|ADD|ADDR)[:\s]*', caseSensitive: false), '')
            .trim();
        if (val.isNotEmpty) addressLines.add(val);
        continue;
      }

      if (inAddress) {
        // Stop address collection at known field markers
        if (dlPatterns.any((p) => p.hasMatch(upper)) ||
            upper.contains('VALID') ||
            upper.contains('CLASS') ||
            upper.contains('COV') ||
            upper.contains('DOI') ||
            upper.contains('BLOOD')) {
          inAddress = false;
        } else {
          addressLines.add(line);
        }
        continue;
      }

      // Issuing Authority
      if (upper.contains('AUTHORITY') || upper.contains('RTO') || upper.contains('ISSUED BY')) {
        issuingAuthority = _extractValue(line, lines, i);
        continue;
      }
    }

    return DrivingLicenseDetails(
      name: name,
      fatherName: fatherName,
      dob: dob,
      dlNumber: dlNumber,
      dateOfIssue: dateOfIssue,
      validity: validity,
      address: addressLines.isNotEmpty ? addressLines.join(', ') : null,
      bloodGroup: bloodGroup,
      vehicleClass: vehicleClass,
      issuingAuthority: issuingAuthority,
      rawText: text,
    );
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

  /// Validates DL number format.
  bool get isDlNumberValid =>
      dlNumber != null &&
      RegExp(r'^[A-Z]{2}\d{13,14}$').hasMatch(dlNumber!.replaceAll(RegExp(r'[\s\-]'), ''));

  /// Returns a map of non-null fields for display.
  Map<String, String> toDisplayMap() {
    final map = <String, String>{};
    if (dlNumber != null) map['DL Number'] = dlNumber!;
    if (name != null) map['Name'] = name!;
    if (fatherName != null) map['Father/Husband'] = fatherName!;
    if (dob != null) map['DOB'] = dob!;
    if (bloodGroup != null) map['Blood Group'] = bloodGroup!;
    if (dateOfIssue != null) map['Date of Issue'] = dateOfIssue!;
    if (validity != null) map['Valid Till'] = validity!;
    if (vehicleClass != null) map['Vehicle Class'] = vehicleClass!;
    if (address != null) map['Address'] = address!;
    if (issuingAuthority != null) map['Issuing Authority'] = issuingAuthority!;
    return map;
  }
}
