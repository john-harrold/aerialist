import SwiftUI
import UniformTypeIdentifiers

struct StampPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onStampSelected: (Data) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Stamp Image")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a transparent PNG file to use as a stamp.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Choose File...") {
                    chooseFile()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 150)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            onStampSelected(data)
            dismiss()
        }
    }
}
