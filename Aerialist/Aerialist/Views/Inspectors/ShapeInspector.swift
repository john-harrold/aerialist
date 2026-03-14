import SwiftUI

struct ShapeInspector: View {
    @Bindable var viewModel: DocumentViewModel
    let shapeID: UUID

    private var shape: ShapeAnnotationModel? {
        viewModel.sidecar.shapes.first { $0.id == shapeID }
    }

    var body: some View {
        if let shape = shape {
            Form {
                Section("Shape Properties") {
                    Picker("Type", selection: shapeTypeBinding) {
                        ForEach(ShapeType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    HStack {
                        Text("Stroke Width")
                        Spacer()
                        TextField("", value: strokeWidthBinding, format: .number)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                    }

                    Picker("Line Style", selection: strokeStyleBinding) {
                        ForEach(OutlineStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }

                    ColorPicker("Line Color", selection: strokeColorBinding)
                        .disabled(shape.strokeStyle == .none)
                        .opacity(shape.strokeStyle == .none ? 0.3 : 1)

                    if shape.shapeType == .rectangle || shape.shapeType == .ellipse {
                        Picker("Fill", selection: hasFillBinding) {
                            Text("No").tag(false)
                            Text("Yes").tag(true)
                        }

                        ColorPicker("Fill Color", selection: fillColorBinding)
                            .disabled(shape.fillColor == nil)
                            .opacity(shape.fillColor != nil ? 1 : 0.3)

                        Slider(value: rotationBinding, in: 0...360, step: 1) {
                            Text("Rotation")
                        }
                        LabeledContent("Rotation") {
                            Text("\(Int(shape.rotation))")
                        }
                    }
                }

                Section("Position") {
                    LabeledContent("Page") {
                        Text("\(shape.pageIndex + 1)")
                    }
                    LabeledContent("Position") {
                        Text("(\(Int(shape.bounds.x)), \(Int(shape.bounds.y)))")
                    }
                    LabeledContent("Size") {
                        Text("\(Int(shape.bounds.width)) x \(Int(shape.bounds.height))")
                    }
                }

                Section {
                    Button("Delete Shape", role: .destructive) {
                        let oldSidecar = viewModel.sidecar
                        var updated = viewModel.sidecar
                        updated.shapes.removeAll { $0.id == shapeID }
                        viewModel.sidecar = updated
                        viewModel.selectedAnnotationID = nil
                        viewModel.registerUndo { vm in
                            vm.sidecar = oldSidecar
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 250)
        }
    }

    // MARK: - Bindings

    private var shapeTypeBinding: Binding<ShapeType> {
        Binding(
            get: { shape?.shapeType ?? .rectangle },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].shapeType = newValue
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var strokeWidthBinding: Binding<Double> {
        Binding(
            get: { Double(shape?.strokeWidth ?? 2) },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].strokeWidth = CGFloat(max(1, min(20, newValue)))
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var strokeStyleBinding: Binding<OutlineStyle> {
        Binding(
            get: { shape?.strokeStyle ?? .solid },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].strokeStyle = newValue
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: shape?.strokeColor ?? "#000000") },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].strokeColor = newValue.hexString
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var hasFillBinding: Binding<Bool> {
        Binding(
            get: { shape?.fillColor != nil },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].fillColor = newValue ? "#FFFFFF" : nil
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: shape?.fillColor ?? "#FFFFFF") },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].fillColor = newValue.hexString
                    viewModel.sidecar = updated
                }
            }
        )
    }

    private var rotationBinding: Binding<CGFloat> {
        Binding(
            get: { shape?.rotation ?? 0 },
            set: { newValue in
                var updated = viewModel.sidecar
                if let idx = updated.shapes.firstIndex(where: { $0.id == shapeID }) {
                    updated.shapes[idx].rotation = newValue
                    viewModel.sidecar = updated
                }
            }
        )
    }
}
