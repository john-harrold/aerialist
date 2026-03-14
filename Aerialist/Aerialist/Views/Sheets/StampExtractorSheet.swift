import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StampExtractorSheet: View {
    var onExtracted: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sourceImage: NSImage?
    @State private var processedImage: NSImage?
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var threshold: Double = 0.5
    @State private var tintColor: Color = .black
    @State private var invertExtraction = false
    @State private var rotation: Double = 0.0
    @State private var cropTop: Double = 0.0
    @State private var cropBottom: Double = 0.0
    @State private var cropLeft: Double = 0.0
    @State private var cropRight: Double = 0.0

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Extract Stamp from Image")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if sourceImage == nil {
                fileSelectionView
            } else {
                editorView
            }
        }
        .frame(minWidth: 750, minHeight: 550)
        .frame(idealWidth: 900, idealHeight: 600)
        .onChange(of: brightness) { updatePreview() }
        .onChange(of: contrast) { updatePreview() }
        .onChange(of: threshold) { updatePreview() }
        .onChange(of: tintColor) { updatePreview() }
        .onChange(of: invertExtraction) { updatePreview() }
        .onChange(of: rotation) { updatePreview() }
        .onChange(of: cropTop) { updatePreview() }
        .onChange(of: cropBottom) { updatePreview() }
        .onChange(of: cropLeft) { updatePreview() }
        .onChange(of: cropRight) { updatePreview() }
    }

    // MARK: - File Selection

    private var fileSelectionView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "signature")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select an image to extract a stamp from")
                .foregroundStyle(.secondary)
            Text("The extractor will remove the background and let you\ncrop, rotate, and adjust the color of the extracted content.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Choose Image...") {
                chooseImage()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor

    private var editorView: some View {
        HSplitView {
            // Preview with guide lines
            VStack {
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                GeometryReader { geo in
                    let previewImage = processedImage ?? sourceImage!
                    ZStack {
                        CheckerboardView()
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Image(nsImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                            .overlay {
                                // Guide lines when rotating
                                if rotation != 0 {
                                    guideLines
                                }
                            }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(minWidth: 350)

            // Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Crop section
                    cropControls

                    Divider()

                    // Rotate section
                    rotateControls

                    Divider()

                    // Extraction section
                    extractionControls

                    Divider()

                    // Adjustments section
                    adjustmentControls

                    Divider()

                    // Color section
                    colorControls

                    Divider()

                    // Actions
                    actionButtons
                }
                .padding()
            }
            .frame(minWidth: 290, maxWidth: 310)
        }
    }

    // MARK: - Guide Lines Overlay

    private var guideLines: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let midY = geo.size.height / 2

            ZStack {
                // Horizontal guide
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))

                // Vertical guide
                Path { path in
                    path.move(to: CGPoint(x: midX, y: 0))
                    path.addLine(to: CGPoint(x: midX, y: geo.size.height))
                }
                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
    }

    // MARK: - Control Sections

    private var cropControls: some View {
        Group {
            Text("Crop")
                .font(.subheadline.bold())

            VStack(spacing: 4) {
                sliderRow("Top", value: $cropTop, range: 0...50, format: "%.0f%%", multiplier: 1)
                sliderRow("Bottom", value: $cropBottom, range: 0...50, format: "%.0f%%", multiplier: 1)
                sliderRow("Left", value: $cropLeft, range: 0...50, format: "%.0f%%", multiplier: 1)
                sliderRow("Right", value: $cropRight, range: 0...50, format: "%.0f%%", multiplier: 1)
            }

            HStack {
                Button("Reset Crop") {
                    cropTop = 0; cropBottom = 0; cropLeft = 0; cropRight = 0
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(cropTop == 0 && cropBottom == 0 && cropLeft == 0 && cropRight == 0)
            }
        }
    }

    private var rotateControls: some View {
        Group {
            Text("Rotate")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Angle")
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $rotation, in: -180...180, step: 0.5)
                    Text(String(format: "%.1f\u{00B0}", rotation))
                        .frame(width: 45, alignment: .trailing)
                        .monospacedDigit()
                }
                Text("Guide lines appear to help align content")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button("-90\u{00B0}") { rotation = max(-180, rotation - 90) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("-1\u{00B0}") { rotation = max(-180, rotation - 1) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("0\u{00B0}") { rotation = 0 }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("+1\u{00B0}") { rotation = min(180, rotation + 1) }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("+90\u{00B0}") { rotation = min(180, rotation + 90) }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .font(.caption)
        }
    }

    private var extractionControls: some View {
        Group {
            Text("Extraction")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Threshold")
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $threshold, in: 0.05...0.95, step: 0.01)
                    Text(String(format: "%.0f%%", threshold * 100))
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                }
                Text("Controls how much of the image is treated as foreground")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Toggle("Invert (extract light content from dark background)", isOn: $invertExtraction)
                .font(.caption)
        }
    }

    private var adjustmentControls: some View {
        Group {
            Text("Adjustments")
                .font(.subheadline.bold())

            sliderRow("Brightness", value: $brightness, range: -0.5...0.5, format: "%+.0f%%", multiplier: 100)
            sliderRow("Contrast", value: $contrast, range: 0.2...3.0, format: "%.1fx", multiplier: 1)
        }
    }

    private var colorControls: some View {
        Group {
            Text("Color")
                .font(.subheadline.bold())

            HStack {
                Text("Tint")
                    .frame(width: 70, alignment: .leading)
                ColorPicker("", selection: $tintColor, supportsOpacity: false)
                    .labelsHidden()
                ForEach(presetColors, id: \.name) { preset in
                    Button {
                        tintColor = preset.color
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 20, height: 20)
                            .overlay {
                                if colorsMatch(tintColor, preset.color) {
                                    Circle()
                                        .strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Choose Different Image...") {
                chooseImage()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Add to Library") {
                addToLibrary()
            }
            .buttonStyle(.borderedProminent)
            .disabled(processedImage == nil)
        }
    }

    // MARK: - Helpers

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String, multiplier: Double) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue * multiplier))
                .frame(width: 45, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Preset Colors

    private struct PresetColor {
        let name: String
        let color: Color
    }

    private var presetColors: [PresetColor] {
        [
            PresetColor(name: "Black", color: .black),
            PresetColor(name: "Blue", color: Color(red: 0, green: 0.2, blue: 0.8)),
            PresetColor(name: "Red", color: Color(red: 0.8, green: 0, blue: 0)),
            PresetColor(name: "Green", color: Color(red: 0, green: 0.5, blue: 0)),
            PresetColor(name: "Purple", color: Color(red: 0.5, green: 0, blue: 0.6)),
            PresetColor(name: "Brown", color: Color(red: 0.5, green: 0.25, blue: 0)),
        ]
    }

    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        let nsA = NSColor(a).usingColorSpace(.sRGB) ?? NSColor(a)
        let nsB = NSColor(b).usingColorSpace(.sRGB) ?? NSColor(b)
        return abs(nsA.redComponent - nsB.redComponent) < 0.05
            && abs(nsA.greenComponent - nsB.greenComponent) < 0.05
            && abs(nsA.blueComponent - nsB.blueComponent) < 0.05
    }

    // MARK: - File Selection

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image to extract a stamp from."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let image = NSImage(contentsOf: url) else { return }
            sourceImage = image
            // Reset crop and rotation for new image
            cropTop = 0; cropBottom = 0; cropLeft = 0; cropRight = 0
            rotation = 0
            updatePreview()
        }
    }

    // MARK: - Image Processing

    private func updatePreview() {
        guard let source = sourceImage else { return }
        processedImage = extractStamp(from: source)
    }

    private func extractStamp(from image: NSImage) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else { return nil }

        let srcWidth = cgImage.width
        let srcHeight = cgImage.height

        // Apply crop
        let cropXMin = Int(Double(srcWidth) * cropLeft / 100.0)
        let cropXMax = srcWidth - Int(Double(srcWidth) * cropRight / 100.0)
        let cropYMin = Int(Double(srcHeight) * cropTop / 100.0)
        let cropYMax = srcHeight - Int(Double(srcHeight) * cropBottom / 100.0)

        let cropW = max(1, cropXMax - cropXMin)
        let cropH = max(1, cropYMax - cropYMin)
        let cropRect = CGRect(x: cropXMin, y: cropYMin, width: cropW, height: cropH)

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

        // Apply rotation
        let radians = CGFloat(rotation) * .pi / 180.0
        let rotatedImage: CGImage
        if rotation == 0 {
            rotatedImage = croppedCG
        } else {
            guard let img = rotateImage(croppedCG, radians: radians) else { return nil }
            rotatedImage = img
        }

        let width = rotatedImage.width
        let height = rotatedImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(rotatedImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Get tint color components
        let nsColor = NSColor(tintColor).usingColorSpace(.sRGB) ?? NSColor(tintColor)
        let tintR = UInt8(clamping: Int(nsColor.redComponent * 255))
        let tintG = UInt8(clamping: Int(nsColor.greenComponent * 255))
        let tintB = UInt8(clamping: Int(nsColor.blueComponent * 255))

        let contrastF = Float(contrast)
        let brightnessF = Float(brightness)
        let thresholdF = Float(threshold)

        for i in 0..<(width * height) {
            let offset = i * 4
            let srcAlpha = Float(pixels[offset + 3]) / 255.0

            // Skip fully transparent pixels (from rotation)
            if srcAlpha < 0.01 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                continue
            }

            var r = Float(pixels[offset]) / 255.0
            var g = Float(pixels[offset + 1]) / 255.0
            var b = Float(pixels[offset + 2]) / 255.0

            // Un-premultiply if needed
            if srcAlpha > 0 && srcAlpha < 1 {
                r /= srcAlpha; g /= srcAlpha; b /= srcAlpha
                r = min(1, r); g = min(1, g); b = min(1, b)
            }

            // Apply brightness and contrast
            r = (r - 0.5) * contrastF + 0.5 + brightnessF
            g = (g - 0.5) * contrastF + 0.5 + brightnessF
            b = (b - 0.5) * contrastF + 0.5 + brightnessF

            r = min(1, max(0, r))
            g = min(1, max(0, g))
            b = min(1, max(0, b))

            // Compute luminance
            let lum = 0.299 * r + 0.587 * g + 0.114 * b

            // Determine foreground vs background
            let isForeground: Bool
            if invertExtraction {
                isForeground = lum > thresholdF
            } else {
                isForeground = lum < thresholdF
            }

            if isForeground {
                let distance: Float
                if invertExtraction {
                    distance = (lum - thresholdF) / (1.0 - thresholdF + 0.001)
                } else {
                    distance = (thresholdF - lum) / (thresholdF + 0.001)
                }
                let alpha = min(1.0, max(0.0, distance * 2.0)) * srcAlpha

                pixels[offset] = tintR
                pixels[offset + 1] = tintG
                pixels[offset + 2] = tintB
                pixels[offset + 3] = UInt8(alpha * 255)
            } else {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }

        guard let outputCG = context.makeImage() else { return nil }
        return NSImage(cgImage: outputCG, size: NSSize(width: width, height: height))
    }

    /// Rotate a CGImage by the given radians, expanding the canvas to fit.
    private func rotateImage(_ image: CGImage, radians: CGFloat) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)

        // Compute rotated bounding box
        let sinA = abs(sin(radians))
        let cosA = abs(cos(radians))
        let newW = Int(ceil(w * cosA + h * sinA))
        let newH = Int(ceil(w * sinA + h * cosA))

        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: newW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Clear to transparent
        context.clear(CGRect(x: 0, y: 0, width: newW, height: newH))

        // Move origin to center, rotate, then draw centered
        context.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        context.rotate(by: radians)
        context.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))

        return context.makeImage()
    }

    // MARK: - Add to Library

    private func addToLibrary() {
        guard let image = processedImage else { return }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        onExtracted(pngData)
        dismiss()
    }
}

// MARK: - Checkerboard Background

private struct CheckerboardView: View {
    let squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.9) : Color(white: 0.75))
                    )
                }
            }
        }
    }
}
