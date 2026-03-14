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
                // File selection
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select an image to extract a stamp from")
                        .foregroundStyle(.secondary)
                    Text("The extractor will remove the background and let you\nadjust the color of the extracted content.")
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
            } else {
                // Editor
                HSplitView {
                    // Preview
                    VStack {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        GeometryReader { geo in
                            let previewImage = processedImage ?? sourceImage!
                            ZStack {
                                // Checkerboard background to show transparency
                                CheckerboardView()
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Image(nsImage: previewImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(8)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .frame(minWidth: 300)

                    // Controls
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
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

                            Divider()

                            Group {
                                Text("Adjustments")
                                    .font(.subheadline.bold())

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Brightness")
                                            .frame(width: 70, alignment: .leading)
                                        Slider(value: $brightness, in: -0.5...0.5, step: 0.01)
                                        Text(String(format: "%+.0f%%", brightness * 100))
                                            .frame(width: 40, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Contrast")
                                            .frame(width: 70, alignment: .leading)
                                        Slider(value: $contrast, in: 0.2...3.0, step: 0.05)
                                        Text(String(format: "%.1fx", contrast))
                                            .frame(width: 40, alignment: .trailing)
                                            .monospacedDigit()
                                    }
                                }
                            }

                            Divider()

                            Group {
                                Text("Color")
                                    .font(.subheadline.bold())

                                HStack {
                                    Text("Tint")
                                        .frame(width: 70, alignment: .leading)
                                    ColorPicker("", selection: $tintColor, supportsOpacity: false)
                                        .labelsHidden()
                                    // Preset colors
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

                            Divider()

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
                        .padding()
                    }
                    .frame(minWidth: 280, maxWidth: 300)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .frame(idealWidth: 800, idealHeight: 550)
        .onChange(of: brightness) { updatePreview() }
        .onChange(of: contrast) { updatePreview() }
        .onChange(of: threshold) { updatePreview() }
        .onChange(of: tintColor) { updatePreview() }
        .onChange(of: invertExtraction) { updatePreview() }
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

        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

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
            var r = Float(pixels[offset]) / 255.0
            var g = Float(pixels[offset + 1]) / 255.0
            var b = Float(pixels[offset + 2]) / 255.0

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
                // Calculate opacity from how far past threshold the pixel is
                let distance: Float
                if invertExtraction {
                    distance = (lum - thresholdF) / (1.0 - thresholdF + 0.001)
                } else {
                    distance = (thresholdF - lum) / (thresholdF + 0.001)
                }
                let alpha = min(1.0, max(0.0, distance * 2.0))

                // Apply tint color with computed alpha
                pixels[offset] = tintR
                pixels[offset + 1] = tintG
                pixels[offset + 2] = tintB
                pixels[offset + 3] = UInt8(alpha * 255)
            } else {
                // Background — make transparent
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }

        guard let outputCG = context.makeImage() else { return nil }
        return NSImage(cgImage: outputCG, size: NSSize(width: width, height: height))
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
