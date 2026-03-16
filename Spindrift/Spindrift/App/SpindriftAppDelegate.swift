import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class SpindriftAppDelegate: NSObject, NSApplicationDelegate {
    private var hasLaunched = false
    /// Hold references to collection windows so they aren't released.
    var collectionWindows: [NSWindow] = []

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if !hasLaunched {
            return false
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.hasLaunched = true
        }

        if let bundleURL = Bundle.main.bundleURL as CFURL? {
            LSRegisterURL(bundleURL, true)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenCollection(_:)),
            name: .openCollection,
            object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                if window.identifier?.rawValue.contains("launcher") == true {
                    window.makeKeyAndOrderFront(nil)
                    return false
                }
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.pathExtension.lowercased() == "spindriftcollection" {
                openCollectionWindow(url: url)
            } else {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }
    }

    @objc private func handleOpenCollection(_ notification: Notification) {
        guard let url = notification.object as? URL else { return }
        openCollectionWindow(url: url)
    }

    func openCollectionWindow(url: URL) {
        // Check if already open
        if let existing = collectionWindows.first(where: {
            $0.representedURL == url
        }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let editorView = CollectionEditorView(fileURL: url)
        let hostingView = NSHostingView(rootView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = url.deletingPathExtension().lastPathComponent
        window.representedURL = url
        window.center()
        window.setFrameAutosaveName("Collection-\(url.lastPathComponent)")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        collectionWindows.append(window)

        // Clean up reference when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] note in
            guard let closedWindow = note.object as? NSWindow else { return }
            Task { @MainActor in
                self?.collectionWindows.removeAll { $0 === closedWindow }
            }
        }
    }
}
