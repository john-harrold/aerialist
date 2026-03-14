import SwiftUI
import UniformTypeIdentifiers

struct StampToolbar: View {
    var stampLibrary: StampLibrary
    @Binding var selectedStampID: UUID?
    var onStampSelected: (Data) -> Void
    @State private var showExtractor = false

    var body: some View {
        HStack(spacing: 12) {
            if stampLibrary.stamps.isEmpty {
                Text("No saved stamps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(stampLibrary.stamps) { stamp in
                            stampThumbnail(stamp)
                        }
                    }
                }
            }

            Divider()
                .frame(height: 28)

            Button {
                addStampFromFile()
            } label: {
                Label("Add Stamp...", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Add stamp from PNG or PDF file")

            Button {
                showExtractor = true
            } label: {
                Label("Extract Stamp...", systemImage: "wand.and.stars")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Extract stamp from image (remove background, change color)")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .sheet(isPresented: $showExtractor) {
            StampExtractorSheet { pngData in
                stampLibrary.addStamp(imageData: pngData, name: "Extracted Stamp")
            }
        }
    }

    private func stampThumbnail(_ stamp: SavedStamp) -> some View {
        let isSelected = selectedStampID == stamp.id

        return Button {
            if let data = stampLibrary.imageData(for: stamp) {
                selectedStampID = stamp.id
                onStampSelected(data)
            }
        } label: {
            Group {
                if let image = stampLibrary.thumbnail(for: stamp) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .help(stamp.name)
        .contextMenu {
            Button(role: .destructive) {
                if selectedStampID == stamp.id {
                    selectedStampID = nil
                }
                stampLibrary.deleteStamp(id: stamp.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func addStampFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PNG or PDF file to add to your stamp library."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            stampLibrary.addStamp(from: url)
        }
    }
}
