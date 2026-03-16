import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                Text("Spindrift")
                    .font(.largeTitle).bold()
                Text("PDF Reader & Editor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                LauncherButton(
                    title: "Open a File",
                    systemImage: "doc",
                    subtitle: "Open a PDF or collection"
                ) {
                    openFile()
                }

                LauncherButton(
                    title: "Combine Files",
                    systemImage: "doc.on.doc.fill",
                    subtitle: "Create a file collection"
                ) {
                    createCollection()
                }
            }
        }
        .padding(40)
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .spindriftCollection]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let ext = url.pathExtension.lowercased()
            if ext == "spindriftcollection" {
                NotificationCenter.default.post(name: .openCollection, object: url)
            } else {
                Task {
                    try? await openDocument(at: url)
                }
            }
            dismissWindow(id: "launcher")
        }
    }

    private func createCollection() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.spindriftCollection]
        savePanel.nameFieldStringValue = "Untitled.spindriftcollection"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            // Create an empty collection file
            let emptyModel = CollectionModel()
            guard let data = try? JSONEncoder().encode(emptyModel) else { return }
            try? data.write(to: url)

            // Open via notification
            NotificationCenter.default.post(name: .openCollection, object: url)
            dismissWindow(id: "launcher")
        }
    }
}

struct LauncherButton: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160, height: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}
