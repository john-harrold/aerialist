import SwiftUI
import PDFKit

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

@main
struct SpindriftApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { SpindriftDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            HelpCommands()
            CommandGroup(after: .saveItem) {
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

                Button("Export as Text...") {
                    NotificationCenter.default.post(
                        name: .exportAsText,
                        object: nil
                    )
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
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
}

extension Notification.Name {
    static let exportAsPDF = Notification.Name("exportAsPDF")
    static let exportAsWord = Notification.Name("exportAsWord")
    static let exportAsText = Notification.Name("exportAsText")
    static let ocrCurrentPage = Notification.Name("ocrCurrentPage")
    static let ocrAllPages = Notification.Name("ocrAllPages")
    static let combineFiles = Notification.Name("combineFiles")
    static let tableSelect = Notification.Name("tableSelect")
}
