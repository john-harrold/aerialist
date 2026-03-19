import SwiftUI

struct ZOrderSection: View {
    @Bindable var viewModel: DocumentViewModel
    let annotationID: UUID

    var body: some View {
        Section("Arrange") {
            HStack(spacing: 8) {
                Button {
                    viewModel.sendToBack(annotationID)
                } label: {
                    Image(systemName: "square.3.layers.3d.bottom.filled")
                }
                .help("Send to Back")

                Button {
                    viewModel.sendBackward(annotationID)
                } label: {
                    Image(systemName: "square.2.layers.3d.bottom.filled")
                }
                .help("Send Backward")

                Button {
                    viewModel.bringForward(annotationID)
                } label: {
                    Image(systemName: "square.2.layers.3d.top.filled")
                }
                .help("Bring Forward")

                Button {
                    viewModel.bringToFront(annotationID)
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }
                .help("Bring to Front")
            }
            .buttonStyle(.bordered)
        }
    }
}
