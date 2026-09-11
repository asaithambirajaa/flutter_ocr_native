import 'dart:typed_data';

import '../utils/ocr_document_saver.dart';
import '../validators/document_number_validator.dart';
import '../validators/document_type_detector.dart';
import 'aadhaar_details.dart';
import 'cheque_details.dart';
import 'driving_license_details.dart';
import 'ocr_result.dart';
import 'passport_details.dart';
import 'voter_id_details.dart';

/// Unified document details model — same structure for all document types.
class DocumentDetails {
  /// Detected document type.
  final DetectedDocType docType;

  /// Primary document number (Aadhaar, PAN, Passport, DL, EPIC, Account No.).
  final String? documentNumber;

  /// Person's name.
  final String? name;

  /// Father/Husband/Guardian name.
  final String? fatherName;

  /// Date of birth.
  final String? dob;

  /// Gender.
  final String? gender;

  /// Address.
  final String? address;

  /// Whether the document number is valid (checksum/format).
  final bool isValid;

  /// Validation error message. Null if valid.
  final String? validationError;

  /// Extracted face/photo bytes from the document image.
  /// Null if no face detected or not applicable (e.g., cheque).
  final Uint8List? photoBytes;

  /// Additional type-specific fields (e.g., IFSC, vehicle class, nationality).
  final Map<String, String> extraFields;

  /// Raw OCR text.
  final String rawText;

  const DocumentDetails({
    required this.docType,
    this.documentNumber,
    this.name,
    this.fatherName,
    this.dob,
    this.gender,
    this.address,
    this.isValid = false,
    this.validationError,
    this.photoBytes,
    this.extraFields = const {},
    required this.rawText,
  });

  /// Parses OCR result into a unified document details model.
  /// Auto-detects document type if not provided.
  /// Use [imageBytes] to extract face photo from the document.
  static Future<DocumentDetails> fromResult(
    OcrResult result, {
    DetectedDocType? type,
    Uint8List? imageBytes,
  }) async {
    final docType = type ?? DocumentTypeDetector.detect(result.text);
    final details = DocumentDetails.fromResultSync(result, docType);

    // Extract face for ID documents (not cheque/unknown)
    if (imageBytes != null &&
        docType != DetectedDocType.cheque &&
        docType != DetectedDocType.unknown &&
        OcrDocumentSaver.isFaceExtractionSupported) {
      final face = await OcrDocumentSaver.extractFace(imageBytes);
      if (face != null) return details._copyWith(photoBytes: face);
    }
    return details;
  }

  /// Synchronous parsing without face extraction.
  factory DocumentDetails.fromResultSync(OcrResult result, [DetectedDocType? type]) {
    final docType = type ?? DocumentTypeDetector.detect(result.text);
    final DocumentDetails base;
    switch (docType) {
      case DetectedDocType.aadhaar:        base = _fromAadhaar(result); break;
      case DetectedDocType.pan:            base = _fromPan(result); break;
      case DetectedDocType.passport:       base = _fromPassport(result); break;
      case DetectedDocType.drivingLicense: base = _fromDL(result); break;
      case DetectedDocType.voterId:        base = _fromVoterId(result); break;
      case DetectedDocType.cheque:         base = _fromCheque(result); break;
      case DetectedDocType.unknown:
        return _mergeFromLabelValueText(
          DocumentDetails(docType: DetectedDocType.unknown, rawText: result.text),
          result.text,
        );
    }
    // For known types, fill any still-null fields from label:value pairs in the text
    return _mergeFromLabelValueText(base, result.text);
  }

  /// Parses directly from OCR text (no face extraction).
  factory DocumentDetails.fromText(String text, [DetectedDocType? type]) =>
      DocumentDetails.fromResultSync(OcrResult(text: text, blocks: []), type);

  /// Whether this document type typically contains a photo.
  bool get hasPhoto => photoBytes != null;

  static DocumentDetails _fromAadhaar(OcrResult result) {
    // Use rawText (unmasked) for extraction
    final rawText = result.rawText;
    final details = AadhaarDetails.fromText(rawText);
    String? aadhaarNumber = details.aadhaarNumber;

    // Fallback: use extractAadhaar on raw text
    aadhaarNumber ??= DocumentNumberValidator.extractAadhaar(rawText);

    // Second fallback: look for any 12-digit number in raw text
    if (aadhaarNumber == null) {
      final match = RegExp(r'(?<!\d)(\d{4})[\s\-]*(\d{4})[\s\-]*(\d{4})(?!\d)')
          .firstMatch(rawText);
      if (match != null) {
        aadhaarNumber = match.group(0);
      }
    }

    final digits = aadhaarNumber?.replaceAll(RegExp(r'[\s\-]'), '');
    final error = digits != null
        ? DocumentNumberValidator.validateAadhaar(digits)
        : 'Aadhaar number not found';

    return DocumentDetails(
      docType: DetectedDocType.aadhaar,
      documentNumber: aadhaarNumber,
      name: details.name,
      fatherName: details.fatherName,
      dob: details.dob,
      gender: details.gender,
      address: details.address,
      isValid: error == null,
      validationError: error,
      rawText: result.text,
    );
  }

  static DocumentDetails _fromPan(OcrResult result) {
    final text = result.text;
    final upper = text.toUpperCase();
    // extractPAN now handles spaces, misreads, and relaxed 4th char internally
    final pan = DocumentNumberValidator.extractPAN(text)
        ?? DocumentNumberValidator.extractPAN(upper);

    String? name;
    String? fatherName;
    String? dob;

    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final upperLines = lines.map((l) => l.toUpperCase()).toList();

    for (int i = 0; i < lines.length; i++) {
      final line = upperLines[i];

      // DOB: match DD/MM/YYYY or DD-MM-YYYY
      if (dob == null) {
        final dobMatch = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})').firstMatch(lines[i]);
        if (dobMatch != null) dob = dobMatch.group(1);
      }

      // Name: keyword line → value is next line OR after slash on same line
      if (line.contains('NAME') && !line.contains('FATHER') && !line.contains('ACCOUNT')) {
        name ??= _extractNameValue(lines, i);
      }

      // Father's name
      if (line.contains('FATHER') || line.contains("FATHER'S")) {
        fatherName ??= _extractNameValue(lines, i);
      }
    }

    // Fallback: all-caps name lines near PAN number
    if ((name == null || fatherName == null) && pan != null) {
      int panIdx = lines.indexWhere((l) => l.toUpperCase().contains(pan));
      if (panIdx == -1) panIdx = 0;
      for (int i = panIdx + 1; i < lines.length; i++) {
        final l = lines[i].trim();
        if (RegExp(r'^[A-Z][A-Z\s]{3,}$').hasMatch(l)) {
          if (name == null) { name = l; continue; }
          if (fatherName == null) { fatherName = l; break; }
        }
      }
    }

    final error = pan != null ? null : 'PAN number not found';
    return DocumentDetails(
      docType: DetectedDocType.pan,
      documentNumber: pan,
      name: name,
      fatherName: fatherName,
      dob: dob,
      isValid: pan != null,
      validationError: error,
      extraFields: {
        if (pan != null && DocumentNumberValidator.panHolderType(pan) != null)
          'Holder Type': DocumentNumberValidator.panHolderType(pan)!,
      },
      rawText: result.text,
    );
  }

  /// Extracts a name value from lines given the index of the keyword line.
  /// Checks: (1) text after '/' on same line, (2) next line if it's letters-only.
  static String? _extractNameValue(List<String> lines, int keywordIdx) {
    // Check after slash on same line: "/ Name" or "नाम / Name"
    final slashIdx = lines[keywordIdx].indexOf('/');
    if (slashIdx != -1) {
      final afterSlash = lines[keywordIdx].substring(slashIdx + 1).trim();
      if (RegExp(r'^[A-Za-z][A-Za-z\s]{2,}$').hasMatch(afterSlash)) return afterSlash;
    }
    // Check next line
    if (keywordIdx + 1 < lines.length) {
      final next = lines[keywordIdx + 1].trim();
      if (RegExp(r'^[A-Za-z][A-Za-z\s]{2,}$').hasMatch(next)) return next;
    }
    return null;
  }

  static DocumentDetails _fromPassport(OcrResult result) {
    final details = PassportDetails.fromText(result.text);
    final error = details.passportNumber != null
        ? DocumentNumberValidator.validatePassport(details.passportNumber!)
        : 'Passport number not found';
    return DocumentDetails(
      docType: DetectedDocType.passport,
      documentNumber: details.passportNumber,
      name: details.name ?? details.surname,
      fatherName: details.fatherName,
      dob: details.dob,
      gender: details.gender,
      isValid: error == null,
      validationError: error,
      extraFields: {
        if (details.surname != null) 'Surname': details.surname!,
        if (details.nationality != null) 'Nationality': details.nationality!,
        if (details.dateOfIssue != null) 'Date of Issue': details.dateOfIssue!,
        if (details.dateOfExpiry != null) 'Date of Expiry': details.dateOfExpiry!,
        if (details.placeOfIssue != null) 'Place of Issue': details.placeOfIssue!,
        if (details.placeOfBirth != null) 'Place of Birth': details.placeOfBirth!,
      },
      rawText: result.text,
    );
  }

  static DocumentDetails _fromDL(OcrResult result) {
    final details = DrivingLicenseDetails.fromText(result.text);
    final error = details.dlNumber != null
        ? DocumentNumberValidator.validateDrivingLicense(details.dlNumber!)
        : 'DL number not found';
    return DocumentDetails(
      docType: DetectedDocType.drivingLicense,
      documentNumber: details.dlNumber,
      name: details.name,
      fatherName: details.fatherName,
      dob: details.dob,
      address: details.address,
      isValid: error == null,
      validationError: error,
      extraFields: {
        if (details.bloodGroup != null) 'Blood Group': details.bloodGroup!,
        if (details.vehicleClass != null) 'Vehicle Class': details.vehicleClass!,
        if (details.dateOfIssue != null) 'Date of Issue': details.dateOfIssue!,
        if (details.validity != null) 'Valid Till': details.validity!,
        if (details.issuingAuthority != null) 'Issuing Authority': details.issuingAuthority!,
      },
      rawText: result.text,
    );
  }

  static DocumentDetails _fromVoterId(OcrResult result) {
    final details = VoterIdDetails.fromText(result.text);
    final error = details.epicNumber != null
        ? DocumentNumberValidator.validateVoterId(details.epicNumber!)
        : 'Voter ID number not found';
    return DocumentDetails(
      docType: DetectedDocType.voterId,
      documentNumber: details.epicNumber,
      name: details.name,
      fatherName: details.fatherName,
      dob: details.dob,
      gender: details.gender,
      address: details.address,
      isValid: error == null,
      validationError: error,
      rawText: result.text,
    );
  }

  static DocumentDetails _fromCheque(OcrResult result) {
    final details = ChequeDetails.fromText(result.text);
    final ifscError = details.ifscCode != null
        ? DocumentNumberValidator.validateIFSC(details.ifscCode!)
        : null;
    final accError = details.accountNumber != null
        ? DocumentNumberValidator.validateAccountNumber(details.accountNumber!)
        : null;
    final isValid = (ifscError == null && details.ifscCode != null) ||
        (accError == null && details.accountNumber != null);
    return DocumentDetails(
      docType: DetectedDocType.cheque,
      documentNumber: details.accountNumber,
      name: details.payeeName,
      address: details.address,
      isValid: isValid,
      validationError: isValid ? null : 'No valid cheque details found',
      extraFields: {
        if (details.ifscCode != null) 'IFSC': details.ifscCode!,
        if (details.bankName != null) 'Bank': details.bankName!,
        if (details.branchName != null) 'Branch': details.branchName!,
        if (details.chequeNumber != null) 'Cheque No.': details.chequeNumber!,
        if (details.date != null) 'Date': details.date!,
        if (details.amountInFigures != null) 'Amount': '₹${details.amountInFigures}',
        if (details.amountInWords != null) 'Amount (Words)': details.amountInWords!,
      },
      rawText: result.text,
    );
  }

  /// Returns all non-null fields as a display map.
  /// Returns fields as a display map.
  /// If [maskAadhaar] is true and doc type is Aadhaar, the number is masked.
  Map<String, String> toDisplayMap({bool maskAadhaar = true}) {
    final map = <String, String>{};
    if (documentNumber != null) {
      String displayNumber = documentNumber!;
      if (maskAadhaar && docType == DetectedDocType.aadhaar) {
        displayNumber = _maskAadhaarNumber(displayNumber);
      }
      map['Document No.'] = displayNumber;
    }
    if (name != null) map['Name'] = name!;
    if (fatherName != null) map['Father/Husband'] = fatherName!;
    if (dob != null) map['DOB'] = dob!;
    if (gender != null) map['Gender'] = gender!;
    if (address != null) map['Address'] = address!;
    map.addAll(extraFields);
    return map;
  }

  static String _maskAadhaarNumber(String number) {
    final match = RegExp(r'(?<!\d)(\d{4})([\s\-]+)(\d{4})([\s\-]+)(\d{4})(?!\d)').firstMatch(number);
    if (match != null) {
      return 'XXXX${match.group(2)}XXXX${match.group(4)}${match.group(5)}';
    }
    final digits = number.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 12) {
      return 'XXXX XXXX ${digits.substring(8)}';
    }
    return number;
  }

  // ── Label-value fallback parser ──────────────────────────────────────────

  /// Parses `Label: Value`, `Label - Value`, `Label = Value` pairs from OCR text.
  /// Returns a map of lowercased-trimmed label → trimmed value.
  static Map<String, String> _parseLabelValuePairs(String text) {
    final result = <String, String>{};
    final sep = RegExp(r'^([^:\-=\n]{2,40}?)\s*[:\-=]\s*(.+)$');
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final m = sep.firstMatch(trimmed);
      if (m != null) {
        final label = m.group(1)!.trim().toLowerCase();
        final value = m.group(2)!.trim();
        if (label.isNotEmpty && value.isNotEmpty) result[label] = value;
      }
    }
    return result;
  }

  /// Fills null fields in [base] using label-value pairs parsed from [text].
  /// Known label synonyms are mapped to structured fields; unknowns go to extraFields.
  static DocumentDetails _mergeFromLabelValueText(DocumentDetails base, String text) {
    final pairs = _parseLabelValuePairs(text);
    if (pairs.isEmpty) return base;

    String? resolve(List<String> keys) {
      for (final k in keys) {
        final v = pairs[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final docNum   = base.documentNumber ?? resolve(['document no', 'document no.', 'doc no', 'number', 'id', 'id no', 'id number', 'aadhaar', 'pan', 'passport no', 'dl no', 'epic no', 'account no', 'account number']);
    final name     = base.name       ?? resolve(['name', 'full name', 'applicant name', 'holder name']);
    final father   = base.fatherName ?? resolve(["father's name", 'father name', 'father', 'husband name', "husband's name", 'guardian name']);
    final dob      = base.dob        ?? resolve(['dob', 'date of birth', 'birth date', 'd.o.b', 'd.o.b.']);
    final gender   = base.gender     ?? resolve(['gender', 'sex']);
    final address  = base.address    ?? resolve(['address', 'addr', 'permanent address', 'residential address']);

    // Collect remaining pairs not mapped to core fields as extraFields
    const coreKeys = {
      'document no', 'document no.', 'doc no', 'number', 'id', 'id no', 'id number',
      'aadhaar', 'pan', 'passport no', 'dl no', 'epic no', 'account no', 'account number',
      'name', 'full name', 'applicant name', 'holder name',
      "father's name", 'father name', 'father', 'husband name', "husband's name", 'guardian name',
      'dob', 'date of birth', 'birth date', 'd.o.b', 'd.o.b.',
      'gender', 'sex',
      'address', 'addr', 'permanent address', 'residential address',
    };
    final extra = Map<String, String>.from(base.extraFields);
    for (final entry in pairs.entries) {
      if (!coreKeys.contains(entry.key) && !extra.containsKey(entry.key)) {
        // Capitalise first letter of each word for display
        final displayKey = entry.key.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
        extra.putIfAbsent(displayKey, () => entry.value);
      }
    }

    if (docNum == base.documentNumber && name == base.name && father == base.fatherName &&
        dob == base.dob && gender == base.gender && address == base.address &&
        extra.length == base.extraFields.length) {
      return base; // nothing changed
    }

    return DocumentDetails(
      docType: base.docType,
      documentNumber: docNum,
      name: name,
      fatherName: father,
      dob: dob,
      gender: gender,
      address: address,
      isValid: base.isValid,
      validationError: base.validationError,
      photoBytes: base.photoBytes,
      extraFields: extra,
      rawText: base.rawText,
    );
  }

  /// Whether any meaningful data was extracted.
  bool get hasData =>
      documentNumber != null || name != null || extraFields.isNotEmpty;

  DocumentDetails _copyWith({Uint8List? photoBytes}) {
    return DocumentDetails(
      docType: docType,
      documentNumber: documentNumber,
      name: name,
      fatherName: fatherName,
      dob: dob,
      gender: gender,
      address: address,
      isValid: isValid,
      validationError: validationError,
      photoBytes: photoBytes ?? this.photoBytes,
      extraFields: extraFields,
      rawText: rawText,
    );
  }

  /// Returns a copy with fields mutated — used only in tamper detection tests.
  /// Do NOT use in production code.
  DocumentDetails copyWithTampered({
    String? documentNumber,
    String? name,
  }) =>
      DocumentDetails(
        docType: docType,
        documentNumber: documentNumber ?? this.documentNumber,
        name: name ?? this.name,
        fatherName: fatherName,
        dob: dob,
        gender: gender,
        address: address,
        isValid: isValid,
        validationError: validationError,
        photoBytes: photoBytes,
        extraFields: extraFields,
        rawText: rawText,
      );

  /// Returns a copy with a single display-map field overwritten by label.
  /// Used in debug mode to simulate inline field editing for tamper detection demo.
  /// Do NOT use in production code.
  DocumentDetails copyWithField(String label, String value) {
    final updatedExtra = Map<String, String>.from(extraFields);
    updatedExtra[label] = value;
    return DocumentDetails(
      docType: docType,
      documentNumber: label == 'Document No.' ? value : documentNumber,
      name: label == 'Name' ? value : name,
      fatherName: label == "Father's Name" ? value : fatherName,
      dob: label == 'DOB' ? value : dob,
      gender: label == 'Gender' ? value : gender,
      address: label == 'Address' ? value : address,
      isValid: isValid,
      validationError: validationError,
      photoBytes: photoBytes,
      extraFields: updatedExtra,
      rawText: rawText,
    );
  }
}
