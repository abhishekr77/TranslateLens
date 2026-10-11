import SwiftUI
import AppKit

final class OverlayWindowController: NSWindowController {
    convenience init(initialMode: LensMode = LensMode(source: .en, target: .zhHans),
                     origin: NSPoint? = nil) {
        let originPoint = origin ?? NSPoint(x: 300, y: 300)
        let frame = NSRect(x: originPoint.x, y: originPoint.y, width: 500, height: 200)
        let w = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isMovable = true
        w.isMovableByWindowBackground = true
        w.hidesOnDeactivate = false
        w.acceptsMouseMovedEvents = true
        w.isReleasedWhenClosed = false

        let view = LensRootView(windowRef: w, initialMode: initialMode)
        w.contentView = NSHostingView(rootView: view)
        self.init(window: w)
    }

    func toggleVisibility() {
        guard let w = window else { return }
        if w.isVisible { w.orderOut(nil) } else { w.orderFrontRegardless() }
    }

    func centerOnActiveScreen() {
        guard let w = window,
              let s = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = w.frame
        w.setFrameOrigin(NSPoint(
            x: s.visibleFrame.midX - f.width / 2,
            y: s.visibleFrame.midY - f.height / 2
        ))
        w.orderFrontRegardless()
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
