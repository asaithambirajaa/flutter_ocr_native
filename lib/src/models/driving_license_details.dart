/// Parsed driving license details extracted from OCR text.
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
    // DL number: state code (2 letters) + RTO code (2 digits) + year (4 digits) + serial (7 digits)
    // e.g., DL-0420110149646, TN01 20190012345, KA0120200001234
    final dlPattern = RegExp(r'\b([A-Z]{2}[\-\s]?\d{2}[\-\s]?\d{4}[\-\s]?\d{7})\b');
    final dlPatternAlt = RegExp(r'\b([A-Z]{2}\d{13})\b');
    final bloodGroupPattern = RegExp(r'\b(A|B|AB|O)[+\-](ve)?\b', caseSensitive: false);
    final vehicleClassPattern = RegExp(r'\b(LMV|MCWG|HMV|HPMV|HTV|MGV|LMV-NT|MC EX50CC|MC50CC|TRANS)\b', caseSensitive: false);

    bool inAddress = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final upper = line.toUpperCase();

      // DL Number
      if (dlNumber == null) {
        final match = dlPattern.firstMatch(line) ?? dlPatternAlt.firstMatch(line);
        if (match != null) {
          dlNumber = match.group(0)?.replaceAll(' ', '');
          continue;
        }
        if (upper.contains('DL NO') || upper.contains('LICENCE NO') || upper.contains('LICENSE NO')) {
          final val = _extractValue(line, lines, i);
          if (val != null) dlNumber = val.replaceAll(' ', '');
          continue;
        }
      }

      // Name
      if (upper.contains('NAME') && !upper.contains('FATHER') && !upper.contains('S/O') && !upper.contains('D/O') && name == null) {
        name = _extractValue(line, lines, i);
        continue;
      }

      // Father/Husband name
      if (upper.contains('S/O') || upper.contains('D/O') || upper.contains('W/O') || upper.contains('FATHER')) {
        fatherName = line
            .replaceAll(RegExp(r'(S/O|D/O|W/O|Father|FATHER)[:\s]*', caseSensitive: false), '')
            .trim();
        if (fatherName.isEmpty && i + 1 < lines.length) fatherName = lines[i + 1];
        continue;
      }

      // DOB
      if (upper.contains('DOB') || upper.contains('BIRTH')) {
        final match = datePattern.firstMatch(line);
        if (match != null) dob = match.group(1);
        continue;
      }

      // Date of Issue
      if (upper.contains('ISSUE') || upper.contains('DOI')) {
        final match = datePattern.firstMatch(line);
        if (match != null) dateOfIssue = match.group(1);
        continue;
      }

      // Validity / Expiry
      if (upper.contains('VALID') || upper.contains('EXPIRY') || upper.contains('NON-TRANSPORT') || upper.contains('TRANSPORT')) {
        final match = datePattern.firstMatch(line);
        if (match != null) validity = match.group(1);
        continue;
      }

      // Blood Group
      final bgMatch = bloodGroupPattern.firstMatch(line);
      if (bgMatch != null && bloodGroup == null) {
        bloodGroup = bgMatch.group(0)?.toUpperCase();
        continue;
      }

      // Vehicle Class
      final vcMatch = vehicleClassPattern.firstMatch(line);
      if (vcMatch != null && vehicleClass == null) {
        vehicleClass = vcMatch.group(0)?.toUpperCase();
        continue;
      }

      // Address
      if (upper.contains('ADDRESS') || upper.contains('ADD')) {
        inAddress = true;
        final val = line.replaceAll(RegExp(r'(Address|ADD)[:\s]*', caseSensitive: false), '').trim();
        if (val.isNotEmpty) addressLines.add(val);
        continue;
      }

      if (inAddress) {
        if (dlPattern.hasMatch(line) || upper.contains('VALID') || upper.contains('CLASS')) {
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
    // Split on colon only (not hyphen, which breaks dates)
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
      dlNumber != null && RegExp(r'^[A-Z]{2}\d{13}$').hasMatch(dlNumber!.replaceAll(RegExp(r'[\s\-]'), ''));

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
