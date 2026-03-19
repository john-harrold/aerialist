import SwiftUI
import AppKit

struct TextBoxesPanel: View {
    @Bindable var viewModel: DocumentViewModel
    var selectedTextBoxID: UUID?

    private var fontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.sidecar.textBoxes.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .frame(width: 260)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Text Boxes")
                .font(.headline)
            Spacer()
            Text("\(viewModel.sidecar.textBoxes.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No text boxes yet")
                .foregroundStyle(.secondary)
            Text("Click on the page to add a text box")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            if let selectedTextBoxID,
               viewModel.sidecar.textBoxes.contains(where: { $0.id == selectedTextBoxID }) {
                propertiesForm(for: selectedTextBoxID)
                    .id(selectedTextBoxID)
                Divider()
            }
            textBoxesList
        }
    }

    // MARK: - Properties Form

    private func propertiesForm(for id: UUID) -> some View {
        let textBox = viewModel.sidecar.textBoxes.first { $0.id == id }
        let hasBg = textBox?.backgroundColor != nil
        let hasOutline = (textBox?.outlineStyle ?? .none) != .none

        return Form {
            Section(header: Text("Properties")) {
                TextField("Text", text: textBinding(for: id), axis: .vertical)
                    .lineLimit(2...6)

                Picker("Font", selection: fontNameBinding(for: id)) {
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: fontSizeBinding(for: id), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }

                ColorPicker("Text Color", selection: textColorBinding(for: id))

                Picker("Background", selection: hasBackgroundBinding(for: id)) {
                    Text("No").tag(false)
                    Text("Yes").tag(true)
                }

                ColorPicker("Background Color", selection: bgColorBinding(for: id))
                    .disabled(!hasBg)
                    .opacity(hasBg ? 1 : 0.3)

                Picker("Outline", selection: outlineStyleBinding(for: id)) {
                    ForEach(OutlineStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }

                ColorPicker("Outline Color", selection: outlineColorBinding(for: id))
                    .disabled(!hasOutline)
                    .opacity(hasOutline ? 1 : 0.3)
            }

            ZOrderSection(viewModel: viewModel, annotationID: id)
        }
        .formStyle(.grouped)
        .frame(maxHeight: 420)
    }

    // MARK: - Text Boxes List

    private var textBoxesList: some View {
        ScrollViewReader { proxy in
            List(sortedTextBoxes) { textBox in
                textBoxRow(textBox)
                    .id(textBox.id)
                    .listRowBackground(
                        textBox.id == selectedTextBoxID
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
            }
            .listStyle(.plain)
            .onAppear {
                if let id = selectedTextBoxID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: selectedTextBoxID) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    private var sortedTextBoxes: [TextBoxAnnotationModel] {
        viewModel.sidecar.textBoxes.sorted { a, b in
            if a.pageIndex != b.pageIndex { return a.pageIndex < b.pageIndex }
            return a.id.uuidString < b.id.uuidString
        }
    }

    private func textBoxRow(_ textBox: TextBoxAnnotationModel) -> some View {
        Button {
            viewModel.goToPage(textBox.pageIndex)
            viewModel.selectedAnnotationID = textBox.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(textBox.text.isEmpty ? "Empty text box" : textBox.text)
                        .lineLimit(2)
                        .foregroundStyle(textBox.text.isEmpty ? .secondary : .primary)
                    Text("Page \(textBox.pageIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Text Box", role: .destructive) {
                var updated = viewModel.sidecar
                updated.textBoxes.removeAll { $0.id == textBox.id }
                viewModel.sidecar = updated
                if viewModel.selectedAnnotationID == textBox.id {
                    viewModel.selectedAnnotationID = nil
                }
            }
        }
    }

    // MARK: - Bindings
    //
    // All setters use explicit read-modify-write to batch mutations into
    // a single `viewModel.sidecar = updated` assignment, preventing
    // multiple annotationRevision increments that cause SwiftUI re-renders.

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.sidecar.textBoxes.first { $0.id == id }?.text ?? "" },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].text = newValue
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func fontNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { viewModel.sidecar.textBoxes.first { $0.id == id }?.fontName ?? "Helvetica" },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].fontName = newValue
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func fontSizeBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.sidecar.textBoxes.first { $0.id == id }?.fontSize ?? 14) },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].fontSize = CGFloat(newValue)
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func textColorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.sidecar.textBoxes.first { $0.id == id }?.color ?? "#000000") },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].color = newValue.hexString
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func hasBackgroundBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.sidecar.textBoxes.first { $0.id == id }?.backgroundColor != nil },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].backgroundColor = newValue ? "#FFFFFF" : nil
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func bgColorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.sidecar.textBoxes.first { $0.id == id }?.backgroundColor ?? "#FFFFFF") },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].backgroundColor = newValue.hexString
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func outlineColorBinding(for id: UUID) -> Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.sidecar.textBoxes.first { $0.id == id }?.outlineColor ?? "#000000") },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].outlineColor = newValue.hexString
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private func outlineStyleBinding(for id: UUID) -> Binding<OutlineStyle> {
        Binding(
            get: { viewModel.sidecar.textBoxes.first { $0.id == id }?.outlineStyle ?? .none },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.textBoxes.firstIndex(where: { $0.id == id }) {
                    updated.textBoxes[idx].outlineStyle = newValue
                    if newValue != .none && updated.textBoxes[idx].outlineColor == nil {
                        updated.textBoxes[idx].outlineColor = "#000000"
                    }
                    if newValue == .none {
                        updated.textBoxes[idx].outlineColor = nil
                    }
                    viewModel.sidecar = updated
                }
            }
        )
    }
}
