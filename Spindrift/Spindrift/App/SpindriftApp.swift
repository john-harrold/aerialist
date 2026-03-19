import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("User Guide") {
                openWindow(id: "help")
            }
        }
    }
}

struct FocusedIsCollectionKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var isCollection: Bool? {
        get { self[FocusedIsCollectionKey.self] }
        set { self[FocusedIsCollectionKey.self] = newValue }
    }
}

@main
struct SpindriftApp: App {
    @NSApplicationDelegateAdaptor(SpindriftAppDelegate.self) var appDelegate
    @FocusedValue(\.isCollection) var isCollection

    var body: some Scene {
        // Launcher window (shown on launch)
        WindowGroup("Welcome to Spindrift", id: "launcher") {
            LauncherView()
        }
        .defaultSize(width: 500, height: 340)
        .windowResizability(.contentSize)

        // PDF document windows
        DocumentGroup(newDocument: { SpindriftDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            HelpCommands()
            CommandGroup(after: .saveItem) {
                Button("Save As...") {
                    NotificationCenter.default.post(name: .saveAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()
                Button("Export as PDF...") {
                    NotificationCenter.default.post(
                        name: .exportAsPDF,
                        object: nil
                    )
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Export as Word...") {
                    NotificationCenter.default.post(
                        name: .exportAsWord,
                        object: nil
                    )
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(isCollection == true)

                Button("Export as Text...") {
                    NotificationCenter.default.post(
                        name: .exportAsText,
                        object: nil
                    )
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(isCollection == true)
            }

            // Replace the default Open with one that supports both PDFs and collections
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    NSDocumentController.shared.newDocument(nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New from Clipboard") {
                    newFromClipboard()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Open...") {
                    openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .importExport) {
                Button("Combine Files...") {
                    NotificationCenter.default.post(
                        name: .combineFiles,
                        object: nil
                    )
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("Tools") {
                Button("OCR Current Page") {
                    NotificationCenter.default.post(
                        name: .ocrCurrentPage,
                        object: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("OCR All Pages") {
                    NotificationCenter.default.post(
                        name: .ocrAllPages,
                        object: nil
                    )
                }
                .keyboardShortcut("o", modifiers: [.command, .shift, .option])

                Divider()

                Button("Select Table Region") {
                    NotificationCenter.default.post(
                        name: .tableSelect,
                        object: nil
                    )
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Window("User Guide", id: "help") {
            HelpView()
        }
        .defaultSize(width: 700, height: 500)
    }

    private func newFromClipboard() {
        let pasteboard = NSPasteboard.general

        // Try PDF data
        if let pdfData = pasteboard.data(forType: .pdf) {
            saveAndOpenPDF(data: pdfData, name: "From Clipboard.pdf")
            return
        }

        // Try image data (TIFF is the native pasteboard format for images)
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            let pdf = PDFDocument()
            let page = PDFPage(image: image)!
            pdf.insert(page, at: 0)
            if let data = pdf.dataRepresentation() {
                saveAndOpenPDF(data: data, name: "From Clipboard.pdf")
                return
            }
        }

        // Try PNG
        if let pngData = pasteboard.data(forType: .png),
           let image = NSImage(data: pngData),
           let page = PDFPage(image: image) {
            let pdf = PDFDocument()
            pdf.insert(page, at: 0)
            if let data = pdf.dataRepresentation() {
                saveAndOpenPDF(data: data, name: "From Clipboard.pdf")
                return
            }
        }

        // Nothing usable
        let alert = NSAlert()
        alert.messageText = "No compatible content on clipboard"
        alert.informativeText = "Copy a PDF, image, or screenshot to the clipboard first."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func saveAndOpenPDF(data: Data, name: String) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        do {
            try data.write(to: tempURL)
            NSDocumentController.shared.openDocument(
                withContentsOf: tempURL,
                display: true
            ) { _, _, _ in }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .spindriftCollection]
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if url.pathExtension.lowercased() == "pdfc" {
                NotificationCenter.default.post(name: .openCollection, object: url)
            } else {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }
    }
}

extension Notification.Name {
    static let exportAsPDF = Notification.Name("exportAsPDF")
    static let exportAsWord = Notification.Name("exportAsWord")
    static let exportAsText = Notification.Name("exportAsText")
    static let ocrCurrentPage = Notification.Name("ocrCurrentPage")
    static let ocrAllPages = Notification.Name("ocrAllPages")
    static let combineFiles = Notification.Name("combineFiles")
    static let tableSelect = Notification.Name("tableSelect")
    static let openCollection = Notification.Name("openCollection")
    static let saveAs = Notification.Name("saveAs")
}
