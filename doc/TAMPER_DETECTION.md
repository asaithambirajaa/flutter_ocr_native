# Document Tamper Detection — Security Overview

**Product:** flutter_ocr_native  
**Version:** 0.3.3+  
**Audience:** Product Managers, Compliance Officers, Security Teams  
**Classification:** Internal

---

## 1. What Is Tamper Detection?

When a user scans an identity document (Aadhaar, PAN, Passport, etc.),
the app extracts text from the image using OCR (Optical Character Recognition).

**Tamper detection** ensures that:

- The extracted data (name, document number, date of birth) has **not been
  modified** after the scan
- The document image has **not been swapped or edited** after the scan
- Any attempt to alter the data is **detected, logged, and blocked**

---

## 2. The Problem It Solves

### Without tamper detection:

```
User scans Aadhaar card
        ↓
App extracts: Name = "Ram Kumar", Aadhaar = "5399 8956 2356"
        ↓
Someone intercepts and changes: Name = "Fake Person"
        ↓
App saves document with WRONG name but VALID Aadhaar number
        ↓
Fraud goes undetected ❌
```

### With tamper detection:

```
User scans Aadhaar card
        ↓
App extracts: Name = "Ram Kumar", Aadhaar = "5399 8956 2356"
App creates a DIGITAL SEAL (hash) of this data immediately
        ↓
Someone intercepts and changes: Name = "Fake Person"
        ↓
App checks: SEAL IS BROKEN → data was changed
        ↓
BLOCKED. Incident logged. Session locked. ✅
```

---

## 3. How the Digital Seal Works (Simple Explanation)

Think of it like a **tamper-evident sticker** on a medicine bottle.

| Physical World | Our App |
|---|---|
| Tamper-evident sticker on bottle | SHA-256 hash of extracted data |
| Sticker breaks if bottle is opened | Hash changes if any field is modified |
| You can see it was tampered | App detects the mismatch |
| Pharmacist refuses to sell it | App blocks save and locks session |
| Incident reported to store manager | Tamper event logged to disk + backend |

### What is SHA-256?

SHA-256 is a mathematical formula that converts any data into a unique
64-character code called a **hash** or **fingerprint**.

```
Input:  "Ram Kumar, 5399 8956 2356, 01/08/1994"
Output: "a3f9c1b2e4d70812f5c3a9b1d2e4f6a8..."

Change ONE character:
Input:  "Ram Kumarx, 5399 8956 2356, 01/08/1994"
Output: "zz99xx11yy223344bb556677cc889900..."
         ↑ Completely different — tamper detected
```

**Key property:** It is mathematically impossible to change the data
and produce the same hash. Even changing a single space produces a
completely different fingerprint.

---

## 4. What Gets Protected

The app creates two separate seals at the moment of scanning:

### Seal 1 — Data Seal (dataHash)
Protects the extracted text fields:

| Field | Example |
|---|---|
| Document Type | Aadhaar Card |
| Document Number | 5399 8956 2356 |
| Name | Ram Kumar |
| Father's Name | Deva Kumar |
| Date of Birth | 01/08/1994 |
| Gender | M |
| Address | 123, MG Road, Bengaluru |

If **any** of these fields are changed after scanning → **TAMPER DETECTED**

### Seal 2 — Image Seal (imageHash)
Protects the raw document image bytes.

If the image is **replaced, cropped differently, or pixel-edited** after
scanning → **TAMPER DETECTED**

---

## 5. When Is Tamper Detection Checked?

```
Timeline of a document scan:
─────────────────────────────────────────────────────────────────

[1] User picks image
        ↓
[2] Image quality check (min 50KB, not blurry)
        ↓
[3] OCR runs — text extracted from image
        ↓
[4] Confidence check (OCR accuracy must be ≥ 75%)
        ↓
[5] ★ SEAL CREATED HERE ★
    dataHash  = fingerprint of all extracted fields
    imageHash = fingerprint of image bytes
    scanId    = unique ID for this scan session
    capturedAt = exact UTC timestamp
    agentId   = who performed the scan
        ↓
[6] Consistency checks run (DOB valid? Document expired?)
        ↓
[7] Audit record saved to disk
        ↓
[8] Results shown to user
        ↓
[9] ★ SEAL VERIFIED HERE ★ (before any save/submit)
    Re-compute fingerprints and compare to stored seals
    If mismatch → TAMPER RESPONSE
```

---

## 6. What Happens When Tampering Is Detected

The response is **immediate and automatic** — no human decision required.

```
TAMPER DETECTED
      │
      ├─── Step 1: LOG
      │    • TamperEvent written to device storage
      │    • Contains: type, reason, scanId, docType,
      │                timestamp, agentId
      │    • In production: POST to security backend API
      │
      ├─── Step 2: WIPE
      │    • All extracted data cleared from device memory
      │    • Image bytes cleared from device memory
      │    • Audit record cleared from device memory
      │    • No sensitive data remains in the app
      │
      ├─── Step 3: LOCK
      │    • Session locked — no further actions possible
      │    • Download button disabled
      │    • View button disabled
      │
      └─── Step 4: ALERT
           • Full-screen red Security Alert dialog
           • Non-dismissible (cannot tap outside to close)
           • Shows: reason, scanId, instructions
           • User must tap "I Understand" to acknowledge
           • Locked screen shown after acknowledgement
```

### What the user sees:

**Security Alert Dialog:**
```
┌─────────────────────────────────────┐
│  🛡️  Security Alert                 │
│                                     │
│  Extracted data has been tampered   │
│  with after capture.                │
│                                     │
│  All captured data has been         │
│  cleared. This incident has been    │
│  logged.                            │
│                                     │
│  Please restart the scan with the   │
│  original document.                 │
│                                     │
│  Scan ID: a3f9c1b2e4d70812          │
│                                     │
│         [ I Understand ]            │
└─────────────────────────────────────┘
```

**Locked Screen (after dialog):**
```
┌─────────────────────────────────────┐
│                                     │
│              🔒                     │
│         Session Locked              │
│                                     │
│  A tamper attempt was detected      │
│  and logged. Start a new scan       │
│  to continue.                       │
│                                     │
│       [ 🔄 Start New Scan ]         │
│                                     │
└─────────────────────────────────────┘
```

---

## 7. The Audit Trail

Every scan — whether tampered or not — produces a permanent audit record.

### Normal Scan Audit Record (JSON):
```json
{
  "docType": "aadhaar",
  "dataHash": "a3f9c1b2e4d70812f5c3a9b1d2e4f6a8b7c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3",
  "imageHash": "f7e2d1c0b9a8f7e6d5c4b3a2f1e0d9c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4f3e2",
  "capturedAt": "2025-06-01T10:30:00.000Z",
  "scanId": "a3f9c1b2e4d70812",
  "agentId": "Raja",
  "sessionId": "1748779800000000"
}
```

### Tamper Event Record (JSON):
```json
{
  "type": "data",
  "reason": "Extracted data has been tampered with after capture.",
  "scanId": "a3f9c1b2e4d70812",
  "docType": "aadhaar",
  "detectedAt": "2025-06-01T10:31:45.000Z",
  "agentId": "Raja"
}
```

### File locations on device:
```
Normal scan:   ocr_audit_1748779800000.json
Tamper event:  ocr_tamper_1748779905000.json
```

Both files are stored in the app's secure support directory and can be
synced to your backend for compliance reporting.

---

## 8. Additional Security Checks

Beyond tamper detection, the system also performs:

### 8.1 Image Quality Gate
| Check | Threshold | Action if Failed |
|---|---|---|
| Image file size | Minimum 50 KB | Rejected before OCR |
| Reason | Images below 50KB are likely blurry or too small to read accurately | — |

### 8.2 OCR Confidence Gate
| Check | Threshold | Action if Failed |
|---|---|---|
| Average text recognition confidence | Minimum 75% | Rejected after OCR |
| Reason | Low confidence means the text may be misread | — |

### 8.3 Document Validity Checks
| Check | Documents | What Is Checked |
|---|---|---|
| Aadhaar checksum | Aadhaar | Verhoeff algorithm — mathematically validates the 12-digit number |
| PAN format | PAN | 10-character format + holder type character |
| Passport format | Passport | 1 letter + 7 digits |
| Document expiry | Passport, Driving License | Expiry date must be in the future |
| Date of birth | All | Must be parseable, age must be 0–120 years |
| Gender value | All | Must be M/F/Male/Female/Transgender |
| Issue vs expiry | Passport, DL | Expiry must be after issue date |

### 8.4 Replay Attack Prevention
Each scan gets a unique `scanId` — a cryptographic fingerprint of:
- The data hash
- The image hash  
- The microsecond timestamp

This means a valid audit record from one scan **cannot be reused** for a
different scan, even if the same document is scanned twice.

---

## 9. Types of Tampering Detected

| Tamper Type | Example | Detected By |
|---|---|---|
| Field edit | Name changed from "Ram Kumar" to "Fake Person" | dataHash mismatch |
| Number edit | Aadhaar changed to a different number | dataHash mismatch |
| DOB edit | Date of birth changed | dataHash mismatch |
| Image swap | Original image replaced with different document | imageHash mismatch |
| Image edit | Pixels modified to change visible text | imageHash mismatch |
| Replay attack | Old valid record reused for new scan | scanId + timestamp check |
| Expired document | Passport expired 2 years ago | Consistency check |
| Impossible DOB | Date of birth in year 1800 | Consistency check |

---

## 10. What Tamper Detection Does NOT Cover

It is important to be transparent about limitations:

| Limitation | Explanation |
|---|---|
| Physical document forgery | If the physical document itself is fake, OCR will extract the fake data. The hash will be valid for that fake data. A separate document authenticity check (hologram, UV, chip) is needed. |
| Tamper before OCR | If the image is edited before being passed to the scanner, the hash will be created from the already-tampered image. |
| Root/jailbroken devices | On a compromised device, an attacker with root access could theoretically modify memory before the hash is created. |
| Network interception | The audit record is currently saved locally. In production it must be POSTed to a backend over HTTPS to prevent local deletion. |

---

## 11. Compliance Relevance

| Regulation / Standard | How This Helps |
|---|---|
| RBI KYC Guidelines | Audit trail proves document was captured unmodified |
| UIDAI Aadhaar Guidelines | Aadhaar number validation + masking + tamper log |
| DPDP Act 2023 (India) | Data integrity evidence; tamper events logged with timestamp |
| ISO 27001 | Access control + audit logging + incident response |
| PCI-DSS (if applicable) | Data integrity controls + incident logging |

---

## 12. Summary for Management

| Question | Answer |
|---|---|
| What does it protect? | Extracted document data and the document image |
| When does it check? | At the moment of saving/submitting — before any data leaves the app |
| What triggers it? | Any change to name, number, DOB, gender, address, or image after scanning |
| What happens on detection? | Data wiped, session locked, incident logged, user alerted |
| Is it logged? | Yes — every tamper event is written to disk with timestamp, scanId, agentId |
| Can it be bypassed? | Not on a normal device. Root/jailbreak is a separate risk. |
| Does it affect normal users? | No — zero impact on legitimate scans |
| Is it automatic? | Yes — no human decision required |

---

## 13. Glossary

| Term | Plain English Meaning |
|---|---|
| SHA-256 | A mathematical formula that creates a unique 64-character fingerprint of any data |
| Hash | The fingerprint produced by SHA-256 |
| dataHash | Fingerprint of the extracted text fields |
| imageHash | Fingerprint of the document image bytes |
| scanId | A unique ID assigned to each individual scan |
| Audit Record | A permanent log entry created for every scan |
| Tamper Event | A log entry created when tampering is detected |
| OCR | Optical Character Recognition — reading text from an image |
| Verhoeff | A mathematical checksum algorithm used to validate Aadhaar numbers |
| Session Lock | Blocking all app actions after a tamper is detected |

---

*Document prepared by the flutter_ocr_native security module.*  
*Last updated: June 2025*
