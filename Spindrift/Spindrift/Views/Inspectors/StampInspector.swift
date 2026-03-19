import SwiftUI

struct StampInspector: View {
    @Bindable var viewModel: DocumentViewModel
    let stampID: UUID

    private var stamp: StampAnnotationModel? {
        viewModel.sidecar.stamps.first { $0.id == stampID }
    }

    var body: some View {
        if let stamp = stamp {
            Form {
                Section("Stamp Properties") {
                    LabeledContent("Page") {
                        Text("\(stamp.pageIndex + 1)")
                    }
                    LabeledContent("Position") {
                        Text("(\(Int(stamp.bounds.x)), \(Int(stamp.bounds.y)))")
                    }
                    LabeledContent("Size") {
                        Text("\(Int(stamp.bounds.width)) x \(Int(stamp.bounds.height))")
                    }

                    Slider(value: opacityBinding, in: 0.1...1.0, step: 0.1) {
                        Text("Opacity")
                    }

                    Slider(value: rotationBinding, in: 0...360, step: 1) {
                        Text("Rotation")
                    }
                    LabeledContent("Rotation") {
                        Text("\(Int(stamp.rotation))")
                    }
                }

                ZOrderSection(viewModel: viewModel, annotationID: stampID)

                Section {
                    Button("Delete Stamp", role: .destructive) {
                        let oldSidecar = viewModel.sidecar
                        var updated = viewModel.sidecar
                        updated.stamps.removeAll { $0.id == stampID }
                        viewModel.sidecar = updated
                        // Select the last remaining stamp to keep inspector open
                        if let lastStamp = updated.stamps.last {
                            viewModel.selectedAnnotationID = lastStamp.id
                        } else {
                            viewModel.selectedAnnotationID = nil
                        }
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

    private var opacityBinding: Binding<CGFloat> {
        Binding(
            get: { stamp?.opacity ?? 1.0 },
            set: { newValue in
                if let index = viewModel.sidecar.stamps.firstIndex(where: { $0.id == stampID }) {
                    viewModel.sidecar.stamps[index].opacity = newValue
                }
            }
        )
    }

    private var rotationBinding: Binding<CGFloat> {
        Binding(
            get: { stamp?.rotation ?? 0 },
            set: { newValue in
                if let index = viewModel.sidecar.stamps.firstIndex(where: { $0.id == stampID }) {
                    viewModel.sidecar.stamps[index].rotation = newValue
                }
            }
        )
    }
}
