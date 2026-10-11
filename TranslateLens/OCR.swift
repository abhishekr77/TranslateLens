import Foundation
import Vision
import CoreGraphics

struct OCRLine {
    let text: String
    let boundingBox: CGRect // normalized, origin bottom-left (Vision convention)
}

enum OCR {
    static func recognize(image: CGImage, languages: [String]) async throws -> [OCRLine] {
        try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { request, error in
                if let error = error { cont.resume(throwing: error); return }
                let obs = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = obs.compactMap { o in
                    guard let c = o.topCandidates(1).first else { return nil }
                    return OCRLine(text: c.string, boundingBox: o.boundingBox)
                }
                cont.resume(returning: lines)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([req]) } catch { cont.resume(throwing: error) }
        }
    }
}
