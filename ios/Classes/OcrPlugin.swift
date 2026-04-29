import Flutter
import UIKit
import Vision

public class OcrPlugin: NSObject, FlutterPlugin {
    private let englishPattern = try! NSRegularExpression(pattern: "[A-Za-z0-9]")
    private let aadhaarPattern = try! NSRegularExpression(pattern: "(\\d{4})[\\s\\-]*(\\d{4})[\\s\\-]*(\\d{4})")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.flutter_ocr_native/text_recognition", binaryMessenger: registrar.messenger())
        let instance = OcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        case "recognizeFromPath":
            guard let path = args?["imagePath"] as? String,
                  let uiImage = UIImage(contentsOfFile: path),
                  let cgImage = uiImage.cgImage else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image path", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "recognizeFromBytes":
            guard let bytes = args?["bytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data),
                  let cgImage = uiImage.cgImage else {
                result(FlutterError(code: "INVALID_ARG", message: "Invalid image bytes", details: nil))
                return
            }
            recognizeText(from: cgImage, result: result)

        case "burnWatermark":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let lines = args["lines"] as? [String: String],
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes and lines required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 90
            let output = burnWatermarkOnImage(uiImage, lines: lines, quality: quality)
            result(output)

        case "compressImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["imageBytes"] as? FlutterStandardTypedData,
                  let uiImage = UIImage(data: bytes.data) else {
                result(FlutterError(code: "INVALID_ARG", message: "imageBytes required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 80
            let compressed = uiImage.jpegData(compressionQuality: CGFloat(quality) / 100.0)
            result(compressed.map { FlutterStandardTypedData(bytes: $0) })

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

        // Find observation containing Aadhaar number
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

            // Calculate proportional mask area (first 8 digits)
            let matchRange = match.range
            let last4Range = match.range(at: 3)
            let charWidth = obsRect.width / CGFloat(nsText.length)

            let maskLeft = obsRect.origin.x + CGFloat(matchRange.location) * charWidth
            let maskRight = obsRect.origin.x + CGFloat(last4Range.location) * charWidth

            maskRect = CGRect(
                x: maskLeft,
                y: obsRect.origin.y,
                width: maskRight - maskLeft,
                height: obsRect.height
            )
            break
        }

        guard let rect = maskRect else { return nil }

        // Draw mask on image
        let size = CGSize(width: imageWidth, height: imageHeight)
        UIGraphicsBeginImageContext(size)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        // Flip context for CGImage drawing
        ctx.translateBy(x: 0, y: imageHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        // Flip back for rect drawing
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -imageHeight)

        // Draw black rectangle with padding
        let padX = rect.width * 0.03
        let padY = rect.height * 0.1
        let paddedRect = CGRect(
            x: max(rect.origin.x - padX, 0),
            y: max(rect.origin.y - padY, 0),
            width: min(rect.width + padX * 2, imageWidth),
            height: min(rect.height + padY * 2, imageHeight)
        )
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(paddedRect)

        guard let maskedImage = UIGraphicsGetImageFromCurrentImageContext(),
              let jpegData = maskedImage.jpegData(compressionQuality: 0.9) else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        return FlutterStandardTypedData(bytes: jpegData)
    }

    private func detectPrinted(observations: [VNRecognizedTextObservation]) -> Bool {
        if observations.isEmpty { return false }

        let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
        if confidences.isEmpty { return true }

        let avgConfidence = Double(confidences.reduce(0, +)) / Double(confidences.count)
        let lowConfCount = confidences.filter { $0 < 0.5 }.count
        let lowConfRatio = Double(lowConfCount) / Double(confidences.count)

        let score = (avgConfidence * 0.5) + ((1.0 - lowConfRatio) * 0.5)
        return score > 0.45
    }

    private func burnWatermarkOnImage(_ image: UIImage, lines: [String: String],
        quality: Int) -> FlutterStandardTypedData? {

        let scaledFontSize = max(image.size.width * 0.03, 36)
        let scaledPadH = image.size.width * 0.02
        let scaledPadV = image.size.width * 0.015
        let lineHeight = scaledFontSize * 1.5
        let wmHeight = CGFloat(lines.count) * lineHeight + scaledPadV * 2
        let totalSize = CGSize(width: image.size.width, height: image.size.height + wmHeight)

        UIGraphicsBeginImageContextWithOptions(totalSize, false, image.scale)
        guard UIGraphicsGetCurrentContext() != nil else { return nil }

        image.draw(at: .zero)

        UIColor(red: 0, green: 0, blue: 0, alpha: 0.7).setFill()
        UIRectFill(CGRect(x: 0, y: image.size.height, width: totalSize.width, height: wmHeight))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: scaledFontSize),
            .foregroundColor: UIColor(red: 1, green: 1, blue: 1, alpha: 0.8)
        ]
        var y = image.size.height + scaledPadV
        for (key, value) in lines {
            let text = "\(key): \(value)" as NSString
            text.draw(at: CGPoint(x: scaledPadH, y: y), withAttributes: attrs)
            y += lineHeight
        }

        guard let output = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()

        let data: Data?
        if quality < 100 {
            data = output.jpegData(compressionQuality: CGFloat(quality) / 100.0)
        } else {
            data = output.pngData()
        }
        guard let finalData = data else { return nil }
        return FlutterStandardTypedData(bytes: finalData)
    }
}
