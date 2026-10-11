import SwiftUI
import AppKit

@main
struct TranslateLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

private let defaultMode = LensMode(source: .en, target: .zhHans)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var lenses: [OverlayWindowController] = []
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        addLens(mode: defaultMode)
        installMenuBarItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLensClose(_:)),
            name: .translateLensClose,
            object: nil
        )
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "character.bubble",
                                 accessibilityDescription: "TranslateLens") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "译"
            }
        }

        let menu = NSMenu()

        // New-lens submenu, one entry per source→target pair.
        let newLensItem = NSMenuItem(title: "New Lens", action: nil, keyEquivalent: "")
        let newLensSub = NSMenu()
        for pair in LensMode.allPairs {
            let title = "\(pair.source.fullName) → \(pair.target.fullName)"
            let m = NSMenuItem(title: title,
                               action: #selector(newLensFromMenu(_:)),
                               keyEquivalent: "")
            m.representedObject = pair.id
            m.target = self
            newLensSub.addItem(m)
        }
        menu.setSubmenu(newLensSub, for: newLensItem)
        menu.addItem(newLensItem)

        // Default-pair shortcut.
        let quickNew = NSMenuItem(title: "New Lens (default)",
                                  action: #selector(newLensDefault),
                                  keyEquivalent: "n")
        quickNew.target = self
        menu.addItem(quickNew)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show / Hide All Lenses",
                     action: #selector(toggleAll), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Center All on Active Screen",
                     action: #selector(centerAll), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "Translate Now (all lenses)",
                     action: #selector(translateNow), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close All Lenses",
                     action: #selector(closeAll), keyEquivalent: "w").target = self
        menu.addItem(withTitle: "Quit TranslateLens",
                     action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        self.statusItem = item
    }

    private func addLens(mode: LensMode) {
        let offset = CGFloat(lenses.count % 8) * 24
        let base = NSPoint(x: 300 + offset, y: 300 - offset)
        let c = OverlayWindowController(initialMode: mode, origin: base)
        c.showWindow(nil)
        lenses.append(c)
    }

    @objc private func newLensDefault() { addLens(mode: defaultMode) }

    @objc private func newLensFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let pair = LensMode.allPairs.first(where: { $0.id == id }) else { return }
        addLens(mode: pair)
    }

    @objc private func toggleAll() {
        let anyVisible = lenses.contains { $0.window?.isVisible == true }
        for l in lenses {
            if anyVisible { l.window?.orderOut(nil) }
            else { l.window?.orderFrontRegardless() }
        }
    }

    @objc private func centerAll() { lenses.forEach { $0.centerOnActiveScreen() } }
    @objc private func translateNow() {
        NotificationCenter.default.post(name: .translateLensRefresh, object: nil)
    }

    @objc private func closeAll() {
        for l in lenses { l.window?.close() }
        lenses.removeAll()
    }

    @objc private func handleLensClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        if let idx = lenses.firstIndex(where: { $0.window === window }) {
            lenses[idx].window?.close()
            lenses.remove(at: idx)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension Notification.Name {
    static let translateLensRefresh = Notification.Name("TranslateLensRefresh")
}
