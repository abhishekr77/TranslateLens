import Foundation
import Combine
import Translation

/// One Translator per lens. Holds the TranslationSession that SwiftUI's
/// `.translationTask` hands us; `translate()` awaits it becoming non-nil.
@MainActor
final class Translator: ObservableObject {
    @Published var session: TranslationSession?
    private var waiters: [CheckedContinuation<TranslationSession, Never>] = []

    func reset() {
        session = nil
    }

    func setSession(_ s: TranslationSession) {
        session = s
        let pending = waiters
        waiters.removeAll()
        for w in pending { w.resume(returning: s) }
        // Trigger the macOS language-pack download sheet on first use of this pair.
        // If the pack is already installed this is a no-op.
        Task {
            do { try await s.prepareTranslation() }
            catch { print("prepareTranslation error: \(error)") }
        }
    }

    func awaitSession() async -> TranslationSession {
        if let s = session { return s }
        return await withCheckedContinuation { cont in waiters.append(cont) }
    }

    func translate(_ strings: [String]) async throws -> [String] {
        guard !strings.isEmpty else { return [] }
        let s = await awaitSession()
        let requests = strings.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: "\($0.offset)")
        }
        var out = Array(repeating: "", count: strings.count)
        let responses = try await s.translations(from: requests)
        for r in responses {
            if let id = r.clientIdentifier, let idx = Int(id) {
                out[idx] = r.targetText
            }
        }
        return out
    }
}
