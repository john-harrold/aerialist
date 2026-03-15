import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct CombineFilesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fileURLs: [URL] = []
    @State private var isProcessing = false
    var onCombine: (PDFDocument) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Combine Files")
                .font(.title2)
                .fontWeight(.semibold)

            List {
                ForEach(Array(fileURLs.enumerated()), id: \.offset) { index, url in
                    HStack {
                        Image(systemName: iconForURL(url))
                        Text(url.lastPathComponent)
                        Spacer()
                        Button {
                            fileURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    fileURLs.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Add Files...") {
                    addFiles()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Combine") {
                    combine()
                }
                .disabled(fileURLs.count < 2 || isProcessing)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .bmp, .gif]
        panel.begin { response in
            guard response == .OK else { return }
            fileURLs.append(contentsOf: panel.urls)
        }
    }

    private func combine() {
        isProcessing = true
        if let combined = FileCombinerService.combine(files: fileURLs) {
            onCombine(combined)
            dismiss()
        }
        isProcessing = false
    }

    private func iconForURL(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "tiff", "bmp", "gif": return "photo"
        default: return "doc"
        }
    }
}
