import SwiftUI

struct TextInspector: View {
    @Bindable var viewModel: DocumentViewModel
    let textBoxID: UUID

    private var textBox: TextBoxAnnotationModel? {
        viewModel.sidecar.textBoxes.first { $0.id == textBoxID }
    }

    var body: some View {
        if textBox != nil {
            inspectorForm
        }
    }

    private var inspectorForm: some View {
        Form {
            propertiesSection
            deleteSection
        }
        .formStyle(.grouped)
        .frame(width: 250)
    }

    @ViewBuilder
    private var propertiesSection: some View {
        Section(header: Text("Text Properties")) {
            TextField("Text", text: textBinding, axis: .vertical)
                .lineLimit(3...6)

            TextField("Font", text: fontNameBinding)

            HStack {
                Text("Size")
                Spacer()
                TextField("", value: fontSizeDoubleBinding, format: .number)
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
            }

            ColorPicker("Color", selection: colorBinding)
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button("Delete Text Box", role: .destructive) {
                var updated = viewModel.sidecar
                updated.textBoxes.removeAll { $0.id == textBoxID }
                viewModel.sidecar = updated
                viewModel.selectedAnnotationID = nil
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { textBox?.text ?? "" },
            set: { newValue in
                if let index = viewModel.sidecar.textBoxes.firstIndex(where: { $0.id == textBoxID }) {
                    viewModel.sidecar.textBoxes[index].text = newValue
                }
            }
        )
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { textBox?.fontName ?? "Helvetica" },
            set: { newValue in
                if let index = viewModel.sidecar.textBoxes.firstIndex(where: { $0.id == textBoxID }) {
                    viewModel.sidecar.textBoxes[index].fontName = newValue
                }
            }
        )
    }

    private var fontSizeDoubleBinding: Binding<Double> {
        Binding(
            get: { Double(textBox?.fontSize ?? 14) },
            set: { newValue in
                if let index = viewModel.sidecar.textBoxes.firstIndex(where: { $0.id == textBoxID }) {
                    viewModel.sidecar.textBoxes[index].fontSize = CGFloat(newValue)
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: textBox?.color ?? "#000000") },
            set: { newValue in
                if let index = viewModel.sidecar.textBoxes.firstIndex(where: { $0.id == textBoxID }) {
                    viewModel.sidecar.textBoxes[index].color = newValue.hexString
                }
            }
        )
    }
}

// MARK: - Color Hex Helpers

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        if hexString.count == 8, let value = UInt64(hexString, radix: 16) {
            let r = Double((value >> 24) & 0xFF) / 255.0
            let g = Double((value >> 16) & 0xFF) / 255.0
            let b = Double((value >> 8) & 0xFF) / 255.0
            let a = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b, opacity: a)
        } else if hexString.count == 6, let value = UInt64(hexString, radix: 16) {
            let r = Double((value >> 16) & 0xFF) / 255.0
            let g = Double((value >> 8) & 0xFF) / 255.0
            let b = Double(value & 0xFF) / 255.0
            self.init(red: r, green: g, blue: b)
        } else {
            self = .black
        }
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = Int(c.alphaComponent * 255)
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
