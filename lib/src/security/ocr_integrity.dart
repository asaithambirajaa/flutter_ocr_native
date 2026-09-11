import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/document_details.dart';
import '../ocr_method_channel.dart';
import '../validators/document_type_detector.dart';

/// Tamper-detection, consistency checks, and audit trail for OCR data.
class OcrIntegrity {
  OcrIntegrity._();

  /// Minimum image size in bytes — below this the image is likely too blurry/small.
  static const int minImageBytes = 50 * 1024; // 50 KB

  /// Minimum average OCR confidence (0.0–1.0) to accept a result.
  /// 0.55 is realistic for real-world document scans with moderate lighting.
  static const double minConfidence = 0.55;

  /// Fallback confidence threshold after image enhancement.
  /// If enhanced OCR still beats this, the result is accepted.
  static const double minConfidenceAfterEnhance = 0.45;

  /// Minimum Laplacian variance — below this the image is considered blurry.
  /// Tune: clear document scan ≈ 200–800+; blurry phone photo ≈ 10–80.
  static const double minSharpnessVariance = 80.0;

  // ── Device security ───────────────────────────────────────────────────────────

  /// Checks if the device is rooted (Android) or jailbroken (iOS).
  /// Returns a [DeviceSecurityResult] with the outcome and reason.
  /// On unsupported platforms (Windows, Linux, macOS) always returns secure.
  ///
  /// [expectedCertHash] — SHA-256 of your release signing certificate
  ///   (colon-separated uppercase hex, e.g. `'A1:B2:C3:...'`).
  ///   Generate with: `keytool -list -v -keystore release.keystore -alias <alias>`
  ///   Leave null to skip the cert check.
  ///
  /// [expectedPackage] — your app's package name (e.g. `'com.yourcompany.app'`).
  ///   Leave null to skip the package name check.
  ///
  /// [checkInstaller] — set `true` in production to block sideloaded APKs.
  ///   Keep `false` during development (ADB installs will be blocked otherwise).
  static Future<DeviceSecurityResult> checkDeviceSecurity({
    String? expectedCertHash,
    String? expectedPackage,
    bool checkInstaller = false,
  }) async {
    try {
      final compromised = await OcrMethodChannel().isDeviceCompromised(
        expectedCertHash: expectedCertHash,
        expectedPackage: expectedPackage,
        checkInstaller: checkInstaller,
      );
      if (compromised) {
        return const DeviceSecurityResult._(
          secure: false,
          reason: 'Device is rooted, jailbroken, or the app has been tampered with. '
              'OCR scanning is not permitted on compromised devices.',
        );
      }
      return const DeviceSecurityResult._(secure: true, reason: 'Device is secure.');
    } catch (_) {
      return const DeviceSecurityResult._(secure: true, reason: 'Device security check not applicable.');
    }
  }

  // ── Hashing ───────────────────────────────────────────────────────────────

  /// SHA-256 of the canonical JSON of extracted fields.
  static String hashDetails(DocumentDetails details) =>
      sha256.convert(utf8.encode(_canonicalJson(details))).toString();

  /// SHA-256 of raw image bytes.
  static String hashImage(Uint8List imageBytes) =>
      sha256.convert(imageBytes).toString();

  // ── Pre-OCR gates ─────────────────────────────────────────────────────────

  /// Returns an error string if [imageBytes] is too small to be a valid scan.
  /// Returns null if the image passes the quality gate.
  static String? checkImageQuality(Uint8List imageBytes) {
    if (imageBytes.lengthInBytes < minImageBytes) {
      final kb = (imageBytes.lengthInBytes / 1024).toStringAsFixed(0);
      return 'Image too small (${kb}KB). Minimum is ${minImageBytes ~/ 1024}KB. '
          'Retake with better lighting and focus.';
    }
    return null;
  }

  /// Checks image sharpness using Laplacian variance on a downsampled grayscale.
  /// Returns an error string if the image is too blurry, null if it passes.
  ///
  /// Works on any image format supported by [dart:ui] (JPEG, PNG, WEBP, BMP).
  /// Samples a centre 200×200 region to keep it fast on large images.
  static Future<String?> checkBlurriness(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 200,
        targetHeight: 200,
      );
      final frame = await codec.getNextFrame();
      final byteData =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();
      final w = 200, h = 200;

      // Convert to grayscale
      final gray = List<int>.generate(w * h, (i) {
        final r = pixels[i * 4];
        final g = pixels[i * 4 + 1];
        final b = pixels[i * 4 + 2];
        return (0.299 * r + 0.587 * g + 0.114 * b).round();
      });

      // Laplacian kernel: sum of |4*center - left - right - top - bottom|
      double sum = 0, sumSq = 0;
      int count = 0;
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final lap = (4 * gray[y * w + x] -
                  gray[(y - 1) * w + x] -
                  gray[(y + 1) * w + x] -
                  gray[y * w + (x - 1)] -
                  gray[y * w + (x + 1)])
              .abs()
              .toDouble();
          sum += lap;
          sumSq += lap * lap;
          count++;
        }
      }
      final mean = sum / count;
      final variance = (sumSq / count) - (mean * mean);

      if (variance < minSharpnessVariance) {
        final pct = ((variance / minSharpnessVariance) * 100).toStringAsFixed(0);
        return 'Image is too blurry (clarity $pct%). '
            'Please retake with better focus and lighting.';
      }
      return null;
    } catch (_) {
      return null; // fail open — don't block on decode error
    }
  }

  /// Returns an error string if average OCR confidence is below [threshold].
  /// Pass [lineConfidences] from result.blocks → lines → confidence.
  /// Returns null if confidence is acceptable.
  static String? checkConfidence(
    List<double> lineConfidences, {
    double threshold = minConfidence,
  }) {
    if (lineConfidences.isEmpty) return null;
    final avg = lineConfidences.reduce((a, b) => a + b) / lineConfidences.length;
    if (avg < threshold) {
      return 'OCR confidence too low (${(avg * 100).toStringAsFixed(0)}%). '
          'Image quality is insufficient — please retake with better lighting.';
    }
    return null;
  }

  // ── Consistency checks ────────────────────────────────────────────────────

  /// Cross-field consistency + expiry checks.
  /// Returns a list of error strings — empty means no issues.
  static List<String> consistencyErrors(DocumentDetails details) {
    final errors = <String>[];
    final now = DateTime.now();

    // DOB: parseable and age 0–120
    if (details.dob != null) {
      final age = _parseAge(details.dob!);
      if (age == null) {
        errors.add('DOB could not be parsed: ${details.dob}');
      } else if (age < 0 || age > 120) {
        errors.add('DOB implies impossible age ($age years): ${details.dob}');
      }
    }

    // Name must not be blank
    if (details.name != null && details.name!.trim().isEmpty) {
      errors.add('Name field is blank');
    }

    // Gender must be a known value
    if (details.gender != null) {
      const known = {'M', 'F', 'MALE', 'FEMALE', 'TRANSGENDER', 'T', 'O'};
      if (!known.contains(details.gender!.toUpperCase())) {
        errors.add('Unexpected gender value: ${details.gender}');
      }
    }

    // Passport checks
    if (details.docType == DetectedDocType.passport) {
      final issue = details.extraFields['Date of Issue'];
      final expiry = details.extraFields['Date of Expiry'];

      if (issue != null && expiry != null) {
        final issueDate = _parseDMY(issue);
        final expiryDate = _parseDMY(expiry);
        if (issueDate != null && expiryDate != null && !expiryDate.isAfter(issueDate)) {
          errors.add('Passport expiry ($expiry) is not after issue date ($issue)');
        }
      }

      // Expiry check
      if (expiry != null) {
        final expiryDate = _parseDMY(expiry);
        if (expiryDate != null && expiryDate.isBefore(now)) {
          errors.add('Passport expired on $expiry');
        }
      }
    }

    // Driving license checks
    if (details.docType == DetectedDocType.drivingLicense) {
      final issue = details.extraFields['Date of Issue'];
      final valid = details.extraFields['Valid Till'];

      if (issue != null && valid != null) {
        final issueDate = _parseDMY(issue);
        final validDate = _parseDMY(valid);
        if (issueDate != null && validDate != null && !validDate.isAfter(issueDate)) {
          errors.add('DL validity ($valid) is not after issue date ($issue)');
        }
      }

      // Expiry check
      if (valid != null) {
        final validDate = _parseDMY(valid);
        if (validDate != null && validDate.isBefore(now)) {
          errors.add('Driving license expired on $valid');
        }
      }
    }

    return errors;
  }

  // ── Verification ──────────────────────────────────────────────────────────

  /// Re-hashes [details] and [imageBytes] and compares against [record].
  /// Call this before submitting / saving to detect any in-memory mutation.
  static OcrVerificationResult verify(
    DocumentDetails details,
    Uint8List imageBytes,
    OcrAuditRecord record,
  ) {
    if (hashDetails(details) != record.dataHash) {
      return const OcrVerificationResult._(
        passed: false,
        reason: 'Extracted data has been tampered with after capture.',
      );
    }
    if (hashImage(imageBytes) != record.imageHash) {
      return const OcrVerificationResult._(
        passed: false,
        reason: 'Document image has been replaced or modified after capture.',
      );
    }
    return const OcrVerificationResult._(passed: true, reason: 'Integrity verified.');
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Persists [record] as a JSON file in the app's support directory.
  /// In production replace this with a POST to your backend.
  static Future<File> persistAuditRecord(OcrAuditRecord record) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(
      '${dir.path}/ocr_audit_${record.capturedAt.millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(record.toJson()));
    return file;
  }

  /// Persists a tamper event to disk and returns the written file.
  /// In production: POST this to your backend security endpoint immediately.
  static Future<File> persistTamperEvent(TamperEvent event) async {
    final dir = await getApplicationSupportDirectory();
    final file = File(
      '${dir.path}/ocr_tamper_${event.detectedAt.millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(event.toJson()));
    return file;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static String _canonicalJson(DocumentDetails d) => jsonEncode({
        'docType': d.docType.name,
        'documentNumber': d.documentNumber,
        'name': d.name,
        'fatherName': d.fatherName,
        'dob': d.dob,
        'gender': d.gender,
        'address': d.address,
        'isValid': d.isValid,
        'extraFields': Map.fromEntries(
          d.extraFields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        ),
      });

  static int? _parseAge(String dob) {
    final d = _parseDMY(dob);
    if (d == null) return null;
    final now = DateTime.now();
    int age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }

  static DateTime? _parseDMY(String s) {
    final parts = s.split(RegExp(r'[/\-]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }
}

/// Immutable audit record created at capture time.
class OcrAuditRecord {
  final String docType;
  final String dataHash;
  final String imageHash;
  final DateTime capturedAt;

  /// Unique ID per scan — prevents replay of a valid record against a different scan.
  final String scanId;

  final String? agentId;
  final String? sessionId;

  const OcrAuditRecord._({
    required this.docType,
    required this.dataHash,
    required this.imageHash,
    required this.capturedAt,
    required this.scanId,
    this.agentId,
    this.sessionId,
  });

  factory OcrAuditRecord.create(
    DocumentDetails details,
    Uint8List imageBytes, {
    String? agentId,
    String? sessionId,
  }) {
    final now = DateTime.now().toUtc();
    return OcrAuditRecord._(
      docType: details.docType.name,
      dataHash: OcrIntegrity.hashDetails(details),
      imageHash: OcrIntegrity.hashImage(imageBytes),
      capturedAt: now,
      // scanId = hash of (dataHash + imageHash + timestamp) — unique per scan
      scanId: sha256
          .convert(utf8.encode(
            '${OcrIntegrity.hashDetails(details)}'
            '${OcrIntegrity.hashImage(imageBytes)}'
            '${now.microsecondsSinceEpoch}',
          ))
          .toString()
          .substring(0, 16),
      agentId: agentId,
      sessionId: sessionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'docType': docType,
        'dataHash': dataHash,
        'imageHash': imageHash,
        'capturedAt': capturedAt.toIso8601String(),
        'scanId': scanId,
        if (agentId != null) 'agentId': agentId,
        if (sessionId != null) 'sessionId': sessionId,
      };

  factory OcrAuditRecord.fromJson(Map<String, dynamic> json) => OcrAuditRecord._(
        docType: json['docType'] as String,
        dataHash: json['dataHash'] as String,
        imageHash: json['imageHash'] as String,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        scanId: json['scanId'] as String? ?? '',
        agentId: json['agentId'] as String?,
        sessionId: json['sessionId'] as String?,
      );
}

/// Result of [OcrIntegrity.verify].
class OcrVerificationResult {
  final bool passed;
  final String reason;

  const OcrVerificationResult._({required this.passed, required this.reason});

  @override
  String toString() => 'OcrVerificationResult(passed: $passed, reason: $reason)';
}

/// Result of [OcrIntegrity.checkDeviceSecurity].
class DeviceSecurityResult {
  final bool secure;
  final String reason;

  const DeviceSecurityResult._({required this.secure, required this.reason});

  @override
  String toString() => 'DeviceSecurityResult(secure: $secure, reason: $reason)';
}

/// Tamper event — created when [OcrIntegrity.verify] fails.
/// Persist immediately and report to your backend.
class TamperEvent {
  /// What was tampered: 'data' or 'image'.
  final String type;
  final String reason;
  final String scanId;
  final String docType;
  final DateTime detectedAt;
  final String? agentId;

  const TamperEvent({
    required this.type,
    required this.reason,
    required this.scanId,
    required this.docType,
    required this.detectedAt,
    this.agentId,
  });

  factory TamperEvent.fromVerification(
    OcrVerificationResult result,
    OcrAuditRecord record,
  ) =>
      TamperEvent(
        type: result.reason.contains('image') ? 'image' : 'data',
        reason: result.reason,
        scanId: record.scanId,
        docType: record.docType,
        detectedAt: DateTime.now().toUtc(),
        agentId: record.agentId,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'reason': reason,
        'scanId': scanId,
        'docType': docType,
        'detectedAt': detectedAt.toIso8601String(),
        if (agentId != null) 'agentId': agentId,
      };
}
