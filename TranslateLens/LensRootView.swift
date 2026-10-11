import SwiftUI
import AppKit
import Translation

enum LensLanguage: String, CaseIterable, Identifiable, Hashable {
    case en, zhHans, nl
    var id: String { rawValue }

    var translationIdentifier: String {
        switch self {
        case .en: return "en"
        case .zhHans: return "zh-Hans"
        case .nl: return "nl"
        }
    }
    var ocrIdentifier: String {
        switch self {
        case .en: return "en-US"
        case .zhHans: return "zh-Hans"
        case .nl: return "nl-NL"
        }
    }
    var shortLabel: String {
        switch self {
        case .en: return "EN"
        case .zhHans: return "中"
        case .nl: return "NL"
        }
    }
    var fullName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "Chinese"
        case .nl: return "Dutch"
        }
    }
    /// Border color is derived from the *target* language.
    var tintColor: Color {
        switch self {
        case .en:     return Color(red: 0.00, green: 0.47, blue: 0.95) // blue
        case .zhHans: return Color(red: 0.87, green: 0.09, blue: 0.14) // PRC red
        case .nl:     return Color(red: 1.00, green: 0.47, blue: 0.00) // Dutch orange
        }
    }
}

struct LensMode: Identifiable, Hashable {
    var source: LensLanguage
    var target: LensLanguage
    var id: String { "\(source.rawValue)->\(target.rawValue)" }

    var sourceLanguage: Locale.Language { Locale.Language(identifier: source.translationIdentifier) }
    var targetLanguage: Locale.Language { Locale.Language(identifier: target.translationIdentifier) }

    /// Hint OCR with the source language first, English second (common fallback).
    var ocrLanguages: [String] {
        var l = [source.ocrIdentifier]
        if source != .en { l.append(LensLanguage.en.ocrIdentifier) }
        return l
    }
    var borderColor: Color { target.tintColor }
    var shortLabel: String { "\(source.shortLabel)→\(target.shortLabel)" }

    /// Every meaningful pair (source ≠ target). Six combinations for three languages.
    static var allPairs: [LensMode] {
        LensLanguage.allCases.flatMap { s in
            LensLanguage.allCases.compactMap { t in
                s == t ? nil : LensMode(source: s, target: t)
            }
        }
    }
}

struct TranslatedLine: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect
}

struct LensRootView: View {
    weak var windowRef: NSWindow?
    @StateObject private var translator = Translator()
    @State private var lines: [TranslatedLine] = []
    @State private var fontSize: CGFloat = 14
    @State private var isBusy = false
    @State private var isPaused = false
    @State private var mode: LensMode
    @State private var translationConfig: TranslationSession.Configuration

    init(windowRef: NSWindow?,
         initialMode: LensMode = LensMode(source: .en, target: .zhHans)) {
        self.windowRef = windowRef
        self._mode = State(initialValue: initialMode)
        self._translationConfig = State(initialValue: TranslationSession.Configuration(
            source: initialMode.sourceLanguage,
            target: initialMode.targetLanguage
        ))
    }

    var body: some View {
        ZStack {
            // When paused, swap the barely-there drag catcher for a frosted
            // backdrop so the translated text is actually readable.
            if isPaused {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.001))
            }
            RoundedRectangle(cornerRadius: 10)
                .stroke(mode.borderColor.opacity(0.95), lineWidth: 2)

            GeometryReader { _ in
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .frame(width: line.rect.width, alignment: .leading)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(3)
                        .position(x: line.rect.midX, y: line.rect.midY)
                }
            }
            .allowsHitTesting(false)

            VStack {
                HStack(spacing: 8) {
                    Button(isPaused ? "▶︎" : "⏸") {
                        isPaused.toggle()
                        if !isPaused { Task { await capture() } }
                    }
                    Button("↻") { Task { await capture() } }
                        .disabled(isBusy)
                    Menu(mode.shortLabel) {
                        ForEach(LensMode.allPairs) { pair in
                            Button("\(pair.source.fullName) → \(pair.target.fullName)") {
                                setMode(pair)
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Switch translation direction")
                    if isBusy { ProgressView().scaleEffect(0.5).frame(width: 14, height: 14) }
                    Spacer()
                    Button("✕") { closeThisLens() }
                        .help("Close this lens")
                }
                .padding(6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(6)
                .padding(6)
                Spacer()
            }
        }
        .translationTask(translationConfig) { session in
            await translator.setSession(session)
            await capture()
        }
        .onAppear { Task { await capture() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { note in
            if (note.object as? NSWindow) === windowRef { Task { await capture() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { note in
            if (note.object as? NSWindow) === windowRef { Task { await capture() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .translateLensRefresh)) { _ in
            Task { await capture() }
        }
    }

    private func setMode(_ newMode: LensMode) {
        guard newMode != mode else { return }
        mode = newMode
        // Keep existing translated lines on screen; the fresh capture that
        // runs once the new TranslationSession arrives will replace them in
        // place with the new target language.
        translator.reset()
        translationConfig = TranslationSession.Configuration(
            source: newMode.sourceLanguage,
            target: newMode.targetLanguage
        )
    }

    private func closeThisLens() {
        guard let w = windowRef else { return }
        NotificationCenter.default.post(name: .translateLensClose, object: w)
    }

    @MainActor
    func capture() async {
        guard !isPaused, !isBusy, let window = windowRef else { return }
        isBusy = true
        defer { isBusy = false }

        let frame = window.frame
        do {
            let image = try await ScreenCapturer.shared.captureRect(frame, excluding: window)
            let ocr = try await OCR.recognize(image: image, languages: mode.ocrLanguages)

            let w = frame.width
            let h = frame.height
            let items: [(text: String, rect: CGRect)] = ocr.map {
                let b = $0.boundingBox
                let rect = CGRect(
                    x: b.origin.x * w,
                    y: (1 - b.origin.y - b.size.height) * h,
                    width: b.size.width * w,
                    height: b.size.height * h
                )
                return ($0.text, rect)
            }
            let grouped = groupIntoLines(items, lensWidth: w)
            guard !grouped.isEmpty else { self.lines = []; return }

            let medianHeight = median(grouped.map { $0.rect.height })
            self.fontSize = max(10, medianHeight * 0.78)

            let translated = try await translator.translate(grouped.map { $0.text })
            self.lines = zip(grouped, translated).map { g, t in
                TranslatedLine(text: t.isEmpty ? g.text : t, rect: g.rect)
            }
        } catch {
            print("capture error: \(error)")
        }
    }

    private func groupIntoLines(_ items: [(text: String, rect: CGRect)], lensWidth: CGFloat)
        -> [(text: String, rect: CGRect)]
    {
        guard !items.isEmpty else { return [] }
        let heights = items.map { $0.rect.height }
        let tol = max(6, median(heights) * 0.8)

        let sorted = items.sorted { $0.rect.midY < $1.rect.midY }
        var buckets: [[(text: String, rect: CGRect)]] = []
        for item in sorted {
            if let bucket = buckets.last,
               let avgY = bucket.map({ $0.rect.midY }).average,
               abs(avgY - item.rect.midY) <= tol {
                buckets[buckets.count - 1].append(item)
            } else {
                buckets.append([item])
            }
        }
        return buckets.map { bucket in
            let ordered = bucket.sorted { $0.rect.minX < $1.rect.minX }
            let joined = ordered.map { $0.text }.joined(separator: " ")
            let minX = ordered.first!.rect.minX
            let minY = ordered.map { $0.rect.minY }.min()!
            let maxY = ordered.map { $0.rect.maxY }.max()!
            let rect = CGRect(
                x: minX,
                y: minY,
                width: max(1, lensWidth - minX - 6),
                height: maxY - minY
            )
            return (joined, rect)
        }
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[s.count / 2]
    }
}

private extension Array where Element == CGFloat {
    var average: CGFloat? {
        isEmpty ? nil : reduce(0, +) / CGFloat(count)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension Notification.Name {
    static let translateLensClose = Notification.Name("TranslateLensClose")
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
