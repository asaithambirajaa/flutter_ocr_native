package com.flutter_ocr_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File

class OcrPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var recognizer: TextRecognizer? = null

    private val englishPattern = Regex("[A-Za-z0-9]")
    // Matches Aadhaar: 4 digits, optional separator, 4 digits, optional separator, 4 digits
    private val aadhaarTextPattern = Regex("(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})")

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.flutter_ocr_native/text_recognition")
        channel.setMethodCallHandler(this)
        recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        recognizer?.close()
        recognizer = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognizeFromPath" -> {
                val path = call.argument<String>("imagePath")
                if (path == null) {
                    result.error("INVALID_ARG", "imagePath is required", null)
                    return
                }
                val bitmap = BitmapFactory.decodeFile(path)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image", null)
                    return
                }
                val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
                processImage(image, bitmap, result)
            }
            "recognizeFromBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("INVALID_ARG", "bytes is required", null)
                    return
                }
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image bytes", null)
                    return
                }
                val image = InputImage.fromBitmap(bitmap, 0)
                processImage(image, bitmap, result)
            }
            "burnWatermark" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                val lines = call.argument<Map<String, String>>("lines")
                val quality = call.argument<Int>("quality") ?: 90

                if (bytes == null || lines == null || lines.isEmpty()) {
                    result.error("INVALID_ARG", "imageBytes and lines are required", null)
                    return
                }

                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image bytes", null)
                    return
                }

                val output = burnWatermarkOnBitmap(bitmap, lines, quality)
                result.success(output)
            }
            "compressImage" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                val quality = call.argument<Int>("quality") ?: 80

                if (bytes == null) {
                    result.error("INVALID_ARG", "imageBytes is required", null)
                    return
                }

                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image bytes", null)
                    return
                }

                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
                bitmap.recycle()
                result.success(stream.toByteArray())
            }
            "extractFace" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                if (bytes == null) {
                    result.error("INVALID_ARG", "imageBytes is required", null)
                    return
                }
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image bytes", null)
                    return
                }
                val image = InputImage.fromBitmap(bitmap, 0)
                extractFaceFromImage(image, bitmap, result)
            }
            "cropImage" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                val x = call.argument<Int>("x") ?: 0
                val y = call.argument<Int>("y") ?: 0
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0

                if (bytes == null || width <= 0 || height <= 0) {
                    result.error("INVALID_ARG", "imageBytes, x, y, width, height required", null)
                    return
                }

                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image", null)
                    return
                }

                val safeX = x.coerceIn(0, bitmap.width - 1)
                val safeY = y.coerceIn(0, bitmap.height - 1)
                val safeW = width.coerceAtMost(bitmap.width - safeX)
                val safeH = height.coerceAtMost(bitmap.height - safeY)

                val cropped = Bitmap.createBitmap(bitmap, safeX, safeY, safeW, safeH)
                val stream = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                cropped.recycle()
                bitmap.recycle()
                result.success(stream.toByteArray())
            }
            "rotateImage" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                val degrees = call.argument<Int>("degrees") ?: 90

                if (bytes == null) {
                    result.error("INVALID_ARG", "imageBytes required", null)
                    return
                }

                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.error("DECODE_ERROR", "Could not decode image", null)
                    return
                }

                val matrix = android.graphics.Matrix()
                matrix.postRotate(degrees.toFloat())
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                val stream = ByteArrayOutputStream()
                rotated.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                rotated.recycle()
                bitmap.recycle()
                result.success(stream.toByteArray())
            }
            "correctOrientation" -> {
                val bytes = call.argument<ByteArray>("imageBytes")
                if (bytes == null) {
                    result.error("INVALID_ARG", "imageBytes required", null)
                    return
                }

                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap == null) {
                    result.success(bytes)
                    return
                }

                // First try EXIF
                val exif = ExifInterface(ByteArrayInputStream(bytes))
                val orientation = exif.getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL
                )
                val exifDegrees = when (orientation) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }

                if (exifDegrees != 0f) {
                    val matrix = android.graphics.Matrix()
                    matrix.postRotate(exifDegrees)
                    val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                    val stream = ByteArrayOutputStream()
                    rotated.compress(Bitmap.CompressFormat.JPEG, 95, stream)
                    rotated.recycle()
                    bitmap.recycle()
                    result.success(stream.toByteArray())
                    return
                }

                // EXIF normal — use a downscaled version for OCR confidence testing
                // to avoid OOM with large images
                val maxTestSize = 1024
                val scaleFactor = if (bitmap.width > maxTestSize || bitmap.height > maxTestSize) {
                    minOf(maxTestSize.toFloat() / bitmap.width, maxTestSize.toFloat() / bitmap.height)
                } else 1f

                val testBitmap = if (scaleFactor < 1f) {
                    Bitmap.createScaledBitmap(
                        bitmap,
                        (bitmap.width * scaleFactor).toInt(),
                        (bitmap.height * scaleFactor).toInt(),
                        true
                    )
                } else bitmap

                val rec = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                val originalInput = InputImage.fromBitmap(testBitmap, 0)
                rec.process(originalInput)
                    .addOnSuccessListener { originalText ->
                        val originalScore = originalText.textBlocks.sumOf { block ->
                            block.lines.sumOf { line ->
                                (line.confidence ?: 0f).toDouble() * line.text.length
                            }
                        }.toFloat()

                        // If original has good readable text, keep it
                        val hasGoodText = originalText.textBlocks.size >= 2 && originalScore > 5f
                        if (hasGoodText) {
                            if (testBitmap !== bitmap) testBitmap.recycle()
                            bitmap.recycle()
                            result.success(bytes)
                            return@addOnSuccessListener
                        }

                        // Original not readable — try other rotations using small test bitmap
                        val otherRotations = listOf(90f, 180f, 270f)
                        var bestDegrees = 0f
                        var bestConfidence = originalScore
                        var pending = otherRotations.size

                        for (deg in otherRotations) {
                            val m = android.graphics.Matrix()
                            m.postRotate(deg)
                            val rotatedTest = Bitmap.createBitmap(testBitmap, 0, 0, testBitmap.width, testBitmap.height, m, true)
                            val input = InputImage.fromBitmap(rotatedTest, 0)
                            rec.process(input)
                                .addOnSuccessListener { text ->
                                    val confidence = text.textBlocks.sumOf { block ->
                                        block.lines.sumOf { line ->
                                            (line.confidence ?: 0f).toDouble() * line.text.length
                                        }
                                    }.toFloat()
                                    synchronized(this) {
                                        if (confidence > bestConfidence) {
                                            bestConfidence = confidence
                                            bestDegrees = deg
                                        }
                                        pending--
                                        if (pending == 0) {
                                            if (testBitmap !== bitmap) testBitmap.recycle()
                                            if (bestDegrees == 0f) {
                                                bitmap.recycle()
                                                result.success(bytes)
                                            } else {
                                                // Apply rotation to the full-size original
                                                val fm = android.graphics.Matrix()
                                                fm.postRotate(bestDegrees)
                                                val final_ = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, fm, true)
                                                val stream = ByteArrayOutputStream()
                                                final_.compress(Bitmap.CompressFormat.JPEG, 95, stream)
                                                final_.recycle()
                                                bitmap.recycle()
                                                result.success(stream.toByteArray())
                                            }
                                        }
                                    }
                                    rotatedTest.recycle()
                                }
                                .addOnFailureListener {
                                    synchronized(this) {
                                        pending--
                                        if (pending == 0) {
                                            if (testBitmap !== bitmap) testBitmap.recycle()
                                            bitmap.recycle()
                                            result.success(bytes)
                                        }
                                    }
                                    rotatedTest.recycle()
                                }
                        }
                    }
                    .addOnFailureListener {
                        if (testBitmap !== bitmap) testBitmap.recycle()
                        bitmap.recycle()
                        result.success(bytes)
                    }
            }
            "dispose" -> {
                recognizer?.close()
                recognizer = null
                result.success(null)
            }
            "renderPdfPage" -> {
                val bytes = call.argument<ByteArray>("pdfBytes")
                val page = call.argument<Int>("page") ?: 0
                val scale = call.argument<Double>("scale") ?: 2.0

                if (bytes == null) {
                    result.error("INVALID_ARG", "pdfBytes is required", null)
                    return
                }
                renderPdfPage(bytes, page, scale, result)
            }
            "getPdfPageCount" -> {
                val bytes = call.argument<ByteArray>("pdfBytes")
                if (bytes == null) {
                    result.error("INVALID_ARG", "pdfBytes is required", null)
                    return
                }
                getPdfPageCount(bytes, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun processImage(image: InputImage, bitmap: Bitmap, result: MethodChannel.Result) {
        val rec = recognizer
        if (rec == null) {
            result.error("NOT_INITIALIZED", "Recognizer not initialized", null)
            return
        }

        rec.process(image)
            .addOnSuccessListener { visionText ->
                val blocks = mutableListOf<Map<String, Any?>>()

                for (block in visionText.textBlocks) {
                    val filteredLines = mutableListOf<Map<String, Any?>>()

                    for (line in block.lines) {
                        val filteredElements = line.elements
                            .filter { isEnglish(it.text) }
                            .map { element ->
                                mapOf(
                                    "text" to extractEnglish(element.text),
                                    "boundingBox" to element.boundingBox?.let { rectToMap(it) },
                                    "confidence" to element.confidence
                                )
                            }

                        if (filteredElements.isNotEmpty()) {
                            val lineText = filteredElements.joinToString(" ") { it["text"] as String }
                            filteredLines.add(mapOf(
                                "text" to lineText,
                                "boundingBox" to line.boundingBox?.let { rectToMap(it) },
                                "confidence" to line.confidence,
                                "elements" to filteredElements
                            ))
                        }
                    }

                    if (filteredLines.isNotEmpty()) {
                        val blockText = filteredLines.joinToString("\n") { it["text"] as String }
                        blocks.add(mapOf(
                            "text" to blockText,
                            "boundingBox" to block.boundingBox?.let { rectToMap(it) },
                            "recognizedLanguage" to block.recognizedLanguage,
                            "lines" to filteredLines
                        ))
                    }
                }

                val fullText = blocks.joinToString("\n") { it["text"] as? String ?: "" }
                val isPrinted = detectPrinted(visionText)
                val maskedImageBytes = maskAadhaarOnImage(bitmap, visionText)

                result.success(mapOf(
                    "text" to fullText,
                    "blocks" to blocks,
                    "isPrinted" to isPrinted,
                    "maskedImageBytes" to maskedImageBytes
                ))
            }
            .addOnFailureListener { e ->
                result.error("RECOGNITION_FAILED", e.message, null)
            }
    }

    /**
     * Finds Aadhaar number in OCR text and masks first 8 digits on the image.
     *
     * Strategy: search every line and block for the 12-digit Aadhaar pattern,
     * then find the bounding boxes of the first 8 digits to mask.
     * Works regardless of card position, rotation, or how ML Kit splits elements.
     */
    private fun maskAadhaarOnImage(bitmap: Bitmap, visionText: Text): ByteArray? {
        val rectsToMask = findAadhaarMaskRects(visionText) ?: return null

        val mutableBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(mutableBitmap)
        val paint = Paint().apply {
            color = Color.BLACK
            style = Paint.Style.FILL
        }

        for (rect in rectsToMask) {
            // Add small padding around the rect for clean masking
            val padX = (rect.width() * 0.05f).toInt()
            val padY = (rect.height() * 0.1f).toInt()
            canvas.drawRect(
                (rect.left - padX).toFloat().coerceAtLeast(0f),
                (rect.top - padY).toFloat().coerceAtLeast(0f),
                (rect.right + padX).toFloat().coerceAtMost(mutableBitmap.width.toFloat()),
                (rect.bottom + padY).toFloat().coerceAtMost(mutableBitmap.height.toFloat()),
                paint
            )
        }

        val stream = ByteArrayOutputStream()
        mutableBitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
        mutableBitmap.recycle()
        return stream.toByteArray()
    }

    /**
     * Searches all lines for the Aadhaar pattern and returns bounding boxes
     * of the first 8 digits to mask.
     */
    private fun findAadhaarMaskRects(visionText: Text): List<Rect>? {
        for (block in visionText.textBlocks) {
            for (line in block.lines) {
                val lineText = line.text
                val match = aadhaarTextPattern.find(lineText) ?: continue

                val first4 = match.groupValues[1]
                val second4 = match.groupValues[2]
                val last4 = match.groupValues[3]

                // Strategy 1: Find matching elements by text
                val rects = findElementRects(line, first4, second4, last4)
                if (rects != null) return rects

                // Strategy 2: If elements don't match individually,
                // compute mask rect from the line bounding box proportionally
                val lineRect = line.boundingBox ?: continue
                return computeProportionalMaskRects(lineRect, lineText, match)
            }
        }

        // Also check across full block text (digits might span lines in rare cases)
        for (block in visionText.textBlocks) {
            val blockText = block.text
            val match = aadhaarTextPattern.find(blockText) ?: continue
            val blockRect = block.boundingBox ?: continue

            return computeProportionalMaskRects(blockRect, blockText, match)
        }

        return null
    }

    /**
     * Tries to find individual element bounding boxes for the first 2 digit groups.
     */
    private fun findElementRects(
        line: Text.Line,
        first4: String,
        second4: String,
        last4: String
    ): List<Rect>? {
        val rects = mutableListOf<Rect>()

        for (element in line.elements) {
            val text = element.text.trim()
            val box = element.boundingBox ?: continue

            when {
                // Element is exactly one of the first 2 groups
                text == first4 || text == second4 -> rects.add(box)

                // Element contains all 12 digits (e.g., "539989562356")
                text.replace(Regex("[\\s\\-]"), "").length == 12 &&
                    text.replace(Regex("[\\s\\-]"), "").all { it.isDigit() } -> {
                    // Mask left 2/3 of the element
                    val maskWidth = (box.width() * 2.0 / 3.0).toInt()
                    rects.add(Rect(box.left, box.top, box.left + maskWidth, box.bottom))
                    return rects
                }

                // Element contains first 8 digits (e.g., "5399 8956")
                text.replace(Regex("[\\s\\-]"), "").let { clean ->
                    clean.length == 8 && clean.all { it.isDigit() } &&
                        clean.startsWith(first4) && clean.endsWith(second4)
                } -> {
                    rects.add(box)
                    return rects
                }

                // Element is "5399 8956 2356" with spaces
                aadhaarTextPattern.containsMatchIn(text) -> {
                    return computeProportionalMaskRects(box, text, aadhaarTextPattern.find(text)!!)
                }
            }
        }

        // Found both first 2 groups as separate elements
        return if (rects.size >= 2) rects.take(2) else null
    }

    /**
     * When we can't find individual element boxes, compute mask area
     * proportionally from the container bounding box based on character positions.
     */
    private fun computeProportionalMaskRects(
        containerRect: Rect,
        fullText: String,
        match: MatchResult
    ): List<Rect> {
        val matchStart = match.range.first
        val matchEnd = match.range.last + 1
        val last4Start = match.groups[3]!!.range.first

        if (fullText.isEmpty()) return emptyList()

        val charWidth = containerRect.width().toDouble() / fullText.length

        // Mask from match start to just before the last 4 digits
        val maskLeft = containerRect.left + (matchStart * charWidth).toInt()
        val maskRight = containerRect.left + (last4Start * charWidth).toInt()

        return listOf(Rect(maskLeft, containerRect.top, maskRight, containerRect.bottom))
    }

    private fun detectPrinted(visionText: Text): Boolean {
        if (visionText.textBlocks.isEmpty()) return false

        val allElements = visionText.textBlocks
            .flatMap { it.lines }
            .flatMap { it.elements }

        if (allElements.isEmpty()) return false

        // Find image bottom boundary from all bounding boxes
        val maxBottom = allElements.mapNotNull { it.boundingBox?.bottom }.maxOrNull() ?: 0
        val bottomThreshold = maxBottom * 0.75

        // Exclude MICR-like elements: mostly digits, low confidence, at bottom of image
        val filteredElements = allElements.filter { element ->
            val box = element.boundingBox
            val isAtBottom = box != null && box.top > bottomThreshold
            val isMostlyDigits = element.text.count { it.isDigit() } > element.text.length * 0.6
            val isLowConf = (element.confidence ?: 1f) < 0.5f
            !(isAtBottom && isMostlyDigits && isLowConf)
        }

        if (filteredElements.isEmpty()) return true

        val confidences = filteredElements.mapNotNull { it.confidence }
        if (confidences.isEmpty()) return true

        val avgConfidence = confidences.average()
        val lowConfCount = confidences.count { it < 0.5f }
        val lowConfRatio = lowConfCount.toDouble() / confidences.size

        val enBlocks = visionText.textBlocks.count { it.recognizedLanguage == "en" }
        val enRatio = if (visionText.textBlocks.isNotEmpty())
            enBlocks.toDouble() / visionText.textBlocks.size else 0.0

        val score = (avgConfidence * 0.4) + ((1.0 - lowConfRatio) * 0.3) + (enRatio * 0.3)
        return score > 0.45
    }

    private fun isEnglish(text: String): Boolean {
        val normalized = normalizeText(text)
        if (normalized.isEmpty()) return false

        val alphaNum = normalized.count { it.isLetterOrDigit() }
        if (alphaNum == 0) return false

        val letters = normalized.replace(Regex("[^A-Za-z]"), "")
        if (letters.length >= 4 && !letters.contains(Regex("[aeiouAEIOU]"))) return false

        return true
    }

    // Normalizes text: replaces Unicode lookalikes with ASCII, then strips remaining non-ASCII
    private fun normalizeText(text: String): String {
        // NFKD normalization converts all Unicode lookalikes to ASCII base forms
        val normalized = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKD)
        // Keep only ASCII printable characters
        return normalized.replace(Regex("[^\\x20-\\x7E]"), "").trim()
    }

    private fun extractEnglish(text: String): String {
        return normalizeText(text)
    }

    private fun burnWatermarkOnBitmap(
        bitmap: Bitmap,
        lines: Map<String, String>,
        quality: Int
    ): ByteArray {
        val scaledFontSize = maxOf(bitmap.width * 0.03f, 36f)
        val scaledPadH = bitmap.width * 0.02f
        val scaledPadV = bitmap.width * 0.015f
        val lineHeight = scaledFontSize * 1.5f
        val wmHeight = (lines.size * lineHeight + scaledPadV * 2).toInt()
        val totalHeight = bitmap.height + wmHeight

        val output = Bitmap.createBitmap(bitmap.width, totalHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)

        canvas.drawBitmap(bitmap, 0f, 0f, null)

        val bgPaint = Paint().apply { color = 0xB3000000.toInt(); style = Paint.Style.FILL }
        canvas.drawRect(0f, bitmap.height.toFloat(), bitmap.width.toFloat(), totalHeight.toFloat(), bgPaint)

        val textPaint = Paint().apply {
            color = 0xCCFFFFFF.toInt()
            textSize = scaledFontSize
            isAntiAlias = true
            isFakeBoldText = true
        }

        var y = bitmap.height.toFloat() + scaledPadV + scaledFontSize
        for ((key, value) in lines) {
            canvas.drawText("$key: $value", scaledPadH, y, textPaint)
            y += lineHeight
        }

        val stream = ByteArrayOutputStream()
        val format = if (quality < 100) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
        output.compress(format, quality, stream)
        output.recycle()

        return stream.toByteArray()
    }

    private fun rectToMap(rect: Rect): Map<String, Any> {
        return mapOf(
            "left" to rect.left.toDouble(),
            "top" to rect.top.toDouble(),
            "width" to rect.width().toDouble(),
            "height" to rect.height().toDouble()
        )
    }

    private fun extractFaceFromImage(image: InputImage, bitmap: Bitmap, result: MethodChannel.Result) {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .build()
        val detector = FaceDetection.getClient(options)

        detector.process(image)
            .addOnSuccessListener { faces ->
                if (faces.isEmpty()) {
                    result.success(null)
                    return@addOnSuccessListener
                }

                // Get the largest face (most likely the ID photo)
                val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }!!
                val box = face.boundingBox

                // Add padding around the face
                val padX = (box.width() * 0.2).toInt()
                val padY = (box.height() * 0.3).toInt()
                val cropRect = Rect(
                    (box.left - padX).coerceAtLeast(0),
                    (box.top - padY).coerceAtLeast(0),
                    (box.right + padX).coerceAtMost(bitmap.width),
                    (box.bottom + padY).coerceAtMost(bitmap.height)
                )

                val cropped = Bitmap.createBitmap(
                    bitmap, cropRect.left, cropRect.top,
                    cropRect.width(), cropRect.height()
                )

                val stream = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                cropped.recycle()

                result.success(stream.toByteArray())
            }
            .addOnFailureListener { e ->
                result.error("FACE_DETECTION_FAILED", e.message, null)
            }
            .addOnCompleteListener { detector.close() }
    }

    private fun renderPdfPage(bytes: ByteArray, page: Int, scale: Double, result: MethodChannel.Result) {
        // Run on background thread to avoid ANR
        Thread {
            try {
                val tempFile = File.createTempFile("pdf_render", ".pdf", context.cacheDir)
                tempFile.writeBytes(bytes)
                val fd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
                val renderer = PdfRenderer(fd)

                if (page < 0 || page >= renderer.pageCount) {
                    renderer.close()
                    fd.close()
                    tempFile.delete()
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        result.error("INVALID_ARG", "Page $page out of range (0-${renderer.pageCount - 1})", null)
                    }
                    return@Thread
                }

                val pdfPage = renderer.openPage(page)

                // Cap dimensions to prevent OOM — max 3000px on either side
                val maxDimension = 3000
                val rawWidth = (pdfPage.width * scale).toInt()
                val rawHeight = (pdfPage.height * scale).toInt()
                val effectiveScale = if (rawWidth > maxDimension || rawHeight > maxDimension) {
                    val scaleW = maxDimension.toDouble() / pdfPage.width
                    val scaleH = maxDimension.toDouble() / pdfPage.height
                    minOf(scaleW, scaleH)
                } else {
                    scale
                }
                val width = (pdfPage.width * effectiveScale).toInt()
                val height = (pdfPage.height * effectiveScale).toInt()

                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)

                // Render without matrix (most compatible across API levels)
                // PdfRenderer renders at the page's native size into the provided bitmap
                // The bitmap size itself controls the output resolution
                pdfPage.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                pdfPage.close()
                renderer.close()
                fd.close()
                tempFile.delete()

                val stream = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                bitmap.recycle()

                val output = stream.toByteArray()
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.success(output)
                }
            } catch (e: OutOfMemoryError) {
                System.gc()
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("OOM", "Image too large to render. Try lower scale.", null)
                }
            } catch (e: Exception) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("PDF_RENDER_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun getPdfPageCount(bytes: ByteArray, result: MethodChannel.Result) {
        try {
            val tempFile = File.createTempFile("pdf_count", ".pdf", context.cacheDir)
            tempFile.writeBytes(bytes)
            val fd = ParcelFileDescriptor.open(tempFile, ParcelFileDescriptor.MODE_READ_ONLY)
            val renderer = PdfRenderer(fd)
            val count = renderer.pageCount
            renderer.close()
            fd.close()
            tempFile.delete()
            result.success(count)
        } catch (e: Exception) {
            result.error("PDF_READ_FAILED", e.message, null)
        }
    }
}
