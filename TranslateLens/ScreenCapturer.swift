import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics

final class ScreenCapturer {
    static let shared = ScreenCapturer()

    /// Capture the given rect, which is given in AppKit global coords
    /// (origin bottom-left of the primary screen, Y increases upward).
    /// Works across multiple displays.
    func captureRect(_ akRect: CGRect, excluding ownWindow: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.current

        // Primary screen is the one with origin (0,0) in AppKit coords.
        // Its height anchors the AppKit → CG conversion for every other display.
        guard let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.screens.first else {
            throw NSError(domain: "cap", code: 2, userInfo: [NSLocalizedDescriptionKey: "no screen"])
        }
        let primaryHeight = primary.frame.height

        // Convert the window rect from AppKit coords to global CG coords
        // (origin top-left of primary display, Y increases downward).
        let cgRect = CGRect(
            x: akRect.origin.x,
            y: primaryHeight - akRect.origin.y - akRect.height,
            width: akRect.width,
            height: akRect.height
        )

        // Pick the SCDisplay whose frame contains (or best intersects) cgRect.
        // SCDisplay.frame is already in global CG coords.
        guard let display = content.displays.max(by: { a, b in
            a.frame.intersection(cgRect).area < b.frame.intersection(cgRect).area
        }), display.frame.intersects(cgRect) else {
            throw NSError(domain: "cap", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "rect not on any display"])
        }

        // sourceRect is in the display's local coords (origin top-left of that display).
        let sourceRect = CGRect(
            x: cgRect.origin.x - display.frame.origin.x,
            y: cgRect.origin.y - display.frame.origin.y,
            width: cgRect.width,
            height: cgRect.height
        )

        let ownNum = CGWindowID(ownWindow.windowNumber)
        let excluded = content.windows.filter { $0.windowID == ownNum }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        // Use the lens's own screen's backing scale, not the primary's.
        let lensScreen = NSScreen.screens.first { screen in
            // Convert screen's AppKit frame to CG and test containment.
            let f = screen.frame
            let cg = CGRect(
                x: f.origin.x,
                y: primaryHeight - f.origin.y - f.height,
                width: f.width,
                height: f.height
            )
            return cg.intersects(cgRect)
        } ?? primary
        let scale = lensScreen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.width = Int(akRect.width * scale)
        config.height = Int(akRect.height * scale)
        config.sourceRect = sourceRect
        config.showsCursor = false
        config.capturesAudio = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
