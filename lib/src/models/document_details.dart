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
    final details = _parse(result, docType);

    // Extract face for ID documents (not cheque/unknown)
    if (imageBytes != null && _hasPhoto(docType) && OcrDocumentSaver.isFaceExtractionSupported) {
      final face = await OcrDocumentSaver.extractFace(imageBytes);
      if (face != null) {
        return details._copyWith(photoBytes: face);
      }
    }
    return details;
  }

  /// Synchronous parsing without face extraction.
  factory DocumentDetails.fromResultSync(OcrResult result, [DetectedDocType? type]) {
    final docType = type ?? DocumentTypeDetector.detect(result.text);
    return _parse(result, docType);
  }

  /// Parses directly from OCR text (no face extraction).
  factory DocumentDetails.fromText(String text, [DetectedDocType? type]) {
    final result = OcrResult(text: text, blocks: []);
    return DocumentDetails.fromResultSync(result, type);
  }

  /// Whether this document type typically has a photo.
  static bool _hasPhoto(DetectedDocType type) =>
      type == DetectedDocType.aadhaar ||
      type == DetectedDocType.pan ||
      type == DetectedDocType.passport ||
      type == DetectedDocType.drivingLicense ||
      type == DetectedDocType.voterId;

  /// Whether this document type typically contains a photo.
  bool get hasPhoto => photoBytes != null;

  static DocumentDetails _parse(OcrResult result, DetectedDocType docType) {
    switch (docType) {
      case DetectedDocType.aadhaar:
        return _fromAadhaar(result);
      case DetectedDocType.pan:
        return _fromPan(result);
      case DetectedDocType.passport:
        return _fromPassport(result);
      case DetectedDocType.drivingLicense:
        return _fromDL(result);
      case DetectedDocType.voterId:
        return _fromVoterId(result);
      case DetectedDocType.cheque:
        return _fromCheque(result);
      case DetectedDocType.unknown:
        return DocumentDetails(
          docType: DetectedDocType.unknown,
          rawText: result.text,
        );
    }
  }

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
    var pan = DocumentNumberValidator.extractPAN(text);

    // Fallback: try extracting from uppercase version (handles mixed case OCR)
    pan ??= DocumentNumberValidator.extractPAN(upper);

    // Fallback: try fixing common OCR misreads (O→0, I→1, S→5)
    if (pan == null) {
      final corrected = upper
          .replaceAll(RegExp(r'(?<=[A-Z]{5})[O]'), '0')
          .replaceAll(RegExp(r'(?<=[A-Z]{5}\d*)[O]'), '0')
          .replaceAll(RegExp(r'(?<=[A-Z]{5}\d*)[I]'), '1')
          .replaceAll(RegExp(r'(?<=[A-Z]{5}\d*)[S]'), '5');
      pan = DocumentNumberValidator.extractPAN(corrected);
    }

    // Parse name and DOB from PAN card text
    String? name;
    String? fatherName;
    String? dob;

    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toUpperCase();
      // DOB patterns
      if (dob == null) {
        final dobMatch = RegExp(r'(\d{2}[/\-]\d{2}[/\-]\d{4})').firstMatch(lines[i]);
        if (dobMatch != null) dob = dobMatch.group(1);
      }
      // Name: line after "Name" or the line that is a proper name (all caps, no digits)
      if (line.contains('NAME') && i + 1 < lines.length) {
        final candidate = lines[i + 1].trim();
        if (RegExp(r'^[A-Za-z\s]+$').hasMatch(candidate) && candidate.length > 2) {
          if (name == null) {
            name = candidate;
          } else {
            fatherName ??= candidate;
          }
        }
      }
      // Father's name keyword
      if ((line.contains('FATHER') || line.contains("FATHER'S")) && i + 1 < lines.length) {
        final candidate = lines[i + 1].trim();
        if (RegExp(r'^[A-Za-z\s]+$').hasMatch(candidate) && candidate.length > 2) {
          fatherName = candidate;
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
}
