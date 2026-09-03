// ── Core reader ───────────────────────────────────────────────────────────────
// OcrPlatformInterface and OcrMethodChannel are internal — not exported.
export 'src/ocr_reader.dart';

// ── OCR result & exceptions ───────────────────────────────────────────────────
// OcrException (base class) is internal — app only catches the two subclasses.
export 'src/models/ocr_exception.dart' hide OcrException;
export 'src/models/ocr_result.dart';

// ── Unified document model ────────────────────────────────────────────────────
// DocumentDetails is the single API for all document types.
// Individual detail models (AadhaarDetails, ChequeDetails, DrivingLicenseDetails,
// PassportDetails, VoterIdDetails) are internal — used only inside the package.
export 'src/models/document_details.dart';

// ── Watermark & image format ──────────────────────────────────────────────────
export 'src/models/ocr_watermark.dart';

// ── Utilities ─────────────────────────────────────────────────────────────────
export 'src/utils/ocr_document_saver.dart';

// ── Validators & detectors ────────────────────────────────────────────────────
export 'src/validators/document_number_validator.dart';
export 'src/validators/document_type_detector.dart';
// HandwritingPolicy is internal — app only uses OcrValidator.validate().
export 'src/validators/ocr_validator.dart' hide HandwritingPolicy;

// ── Security / Integrity ─────────────────────────────────────────────────────
export 'src/security/ocr_integrity.dart';

// ── Widgets ───────────────────────────────────────────────────────────────────
export 'src/widgets/ocr_capture_instructions.dart';
export 'src/widgets/ocr_document_viewer.dart';
export 'src/widgets/ocr_image_cropper.dart';
// OcrDetailsCard and VoterIdDetailsCard are internal — apps build their own UI
// from DocumentDetails.toDisplayMap(). Keeping them internal avoids a redundant
// parallel display API.
