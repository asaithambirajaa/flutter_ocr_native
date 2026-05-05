import Cocoa
import FlutterMacOS
import Vision

public class OcrPlugin: NSObject, FlutterPlugin {
    private let englishPattern = try! NSRegularExpression(pattern: "[A-Za-z0-9]")
    private let aadhaarPattern = try! NSRegularExpression(pattern: "(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.flutter_ocr_native/text_recognition", binaryMessenger: registrar.messenger)
        let instance = OcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "recognizeFromPath":
            guard let path = args?["imagePath"] as? String,
                  let nsImage = NSImage(contentsOfFile: path),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image path", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "recognizeFromBytes":
            guard let bytes = args?["bytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image bytes", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "burnWatermark":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let lines = args["lines"] as? [String: String],
                  let nsImage = NSImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes and lines required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 90
            let output = burnWatermarkOnImage(nsImage, lines: lines, quality: quality)
            result(output)

        case "compressImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let nsImage = NSImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 80
            let compressed = compressToJpeg(nsImage, quality: quality)
            result(compressed)

        case "dispose":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func isEnglish(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return englishPattern.firstMatch(in: text, range: range) != nil
    }

    private func recognizeText(from image: CGImage, result: @escaping FlutterResult) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                result(FlutterError(code: "RECOGNITION_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                result(["text": "", "blocks": [], "isPrinted": false, "maskedImageBytes": NSNull()])
                return
            }

            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            var blocks: [[String: Any]] = []

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                guard self.isEnglish(text) else { continue }

                let box = observation.boundingBox
                let boundingBox: [String: Any] = [
                    "left": box.origin.x * imageWidth,
                    "top": (1 - box.origin.y - box.height) * imageHeight,
                    "width": box.width * imageWidth,
                    "height": box.height * imageHeight
                ]

                let element: [String: Any] = [
                    "text": text,
                    "boundingBox": boundingBox,
                    "confidence": candidate.confidence
                ]

                let line: [String: Any] = [
                    "text": text,
                    "boundingBox": boundingBox,
                    "confidence": candidate.confidence,
                    "elements": [element]
                ]

                blocks.append([
                    "text": text,
                    "boundingBox": boundingBox,
                    "lines": [line]
                ])
            }

            let fullText = blocks.map { $0["text"] as? String ?? "" }.joined(separator: "\n")
            let isPrinted = self.detectPrinted(observations: observations)
            let maskedBytes = self.maskAadhaarOnImage(image: image, observations: observations)

            result([
                "text": fullText,
                "blocks": blocks,
                "isPrinted": isPrinted,
                "maskedImageBytes": maskedBytes as Any
            ])
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                result(FlutterError(code: "RECOGNITION_FAILED", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func maskAadhaarOnImage(image: CGImage, observations: [VNRecognizedTextObservation]) -> FlutterStandardTypedData? {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        var maskRect: CGRect? = nil

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            guard let match = aadhaarPattern.firstMatch(in: text, range: range) else { continue }

            let box = observation.boundingBox
            let obsRect = CGRect(
                x: box.origin.x * imageWidth,
                y: (1 - box.origin.y - box.height) * imageHeight,
                width: box.width * imageWidth,
                height: box.height * imageHeight
            )

            let last4Range = match.range(at: 3)
            let charWidth = obsRect.width / CGFloat(nsText.length)
            let maskLeft = obsRect.origin.x + CGFloat(match.range.location) * charWidth
            let maskRight = obsRect.origin.x + CGFloat(last4Range.location) * charWidth

            maskRect = CGRect(x: maskLeft, y: obsRect.origin.y, width: maskRight - maskLeft, height: obsRect.height)
            break
        }

        guard let rect = maskRect else { return nil }

        let size = NSSize(width: imageWidth, height: imageHeight)
        let nsImage = NSImage(size: size)
        nsImage.lockFocus()

        let ctx = NSGraphicsContext.current!.cgContext
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        let padX = rect.width * 0.03
        let padY = rect.height * 0.1
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(
            x: max(rect.origin.x - padX, 0),
            y: max(rect.origin.y - padY, 0),
            width: min(rect.width + padX * 2, imageWidth),
            height: min(rect.height + padY * 2, imageHeight)
        ))

        nsImage.unlockFocus()

        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }

    private func detectPrinted(observations: [VNRecognizedTextObservation]) -> Bool {
        if observations.isEmpty { return false }
        let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
        if confidences.isEmpty { return true }
        let avg = Double(confidences.reduce(0, +)) / Double(confidences.count)
        let lowCount = confidences.filter { $0 < 0.5 }.count
        let lowRatio = Double(lowCount) / Double(confidences.count)
        return (avg * 0.5 + (1.0 - lowRatio) * 0.5) > 0.45
    }

    private func burnWatermarkOnImage(_ image: NSImage, lines: [String: String], quality: Int) -> FlutterStandardTypedData? {
        let scaledFontSize = max(image.size.width * 0.03, 36)
        let scaledPadH = image.size.width * 0.02
        let scaledPadV = image.size.width * 0.015
        let lineHeight = scaledFontSize * 1.5
        let wmHeight = CGFloat(lines.count) * lineHeight + scaledPadV * 2
        let totalSize = NSSize(width: image.size.width, height: image.size.height + wmHeight)

        let outputImage = NSImage(size: totalSize)
        outputImage.lockFocus()

        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)

        NSColor(red: 0, green: 0, blue: 0, alpha: 0.7).setFill()
        NSRect(x: 0, y: 0, width: totalSize.width, height: wmHeight).fill()

        // Note: macOS coordinate system is flipped (origin bottom-left)
        // Draw watermark at the bottom
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: scaledFontSize),
            .foregroundColor: NSColor(red: 1, green: 1, blue: 1, alpha: 0.8)
        ]
        var y = scaledPadV
        for (key, value) in lines {
            let text = "\(key): \(value)" as NSString
            text.draw(at: NSPoint(x: scaledPadH, y: y), withAttributes: attrs)
            y += lineHeight
        }

        outputImage.unlockFocus()

        guard let tiff = outputImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }

        let data: Data?
        if quality < 100 {
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: CGFloat(quality) / 100.0])
        } else {
            data = bitmap.representation(using: .png, properties: [:])
        }
        guard let finalData = data else { return nil }
        return FlutterStandardTypedData(bytes: finalData)
    }

    private func compressToJpeg(_ image: NSImage, quality: Int) -> FlutterStandardTypedData? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: CGFloat(quality) / 100.0]) else {
            return nil
        }
        return FlutterStandardTypedData(bytes: jpeg)
    }
}
