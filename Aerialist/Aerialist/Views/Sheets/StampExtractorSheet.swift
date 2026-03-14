import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

struct StampExtractorSheet: View {
    var onExtracted: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sourceImage: NSImage?
    @State private var sourceCGImage: CGImage?
    @State private var processedImage: NSImage?
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var threshold: Double = 0.5
    @State private var tintColor: Color = .black
    @State private var invertExtraction = false
    @State private var rotation: Double = 0.0

    // Crop state — normalized 0...1 coordinates relative to displayed image
    @State private var cropRect: CGRect? = nil
    @State private var isCropped = false

    // Debounce timer for slider changes
    @State private var updateTask: Task<Void, Never>?

    // Full-res processed cache (only built on export)
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var body: some View {
        VStack(spacing: 0) {
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
            // Preview
            VStack(spacing: 0) {
                HStack {
                    Text(isCropped ? "Preview (extracted)" : "Drag to select crop region")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if cropRect != nil && !isCropped {
                        Button("Clear Selection") {
                            cropRect = nil
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                GeometryReader { geo in
                    if isCropped, let preview = processedImage {
                        // Show extracted result
                        ZStack {
                            CheckerboardView()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(8)
                            if rotation != 0 {
                                guideLines
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else if let src = sourceImage {
                        // Show source with crop overlay
                        CropOverlayView(
                            image: src,
                            cropRect: $cropRect,
                            rotation: rotation
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .frame(minWidth: 400)

            // Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Crop button
                    cropSection

                    Divider()

                    rotateControls

                    Divider()

                    extractionControls

                    Divider()

                    adjustmentControls

                    Divider()

                    colorControls

                    Divider()

                    actionButtons
                }
                .padding()
            }
            .frame(minWidth: 290, maxWidth: 310)
        }
    }

    // MARK: - Guide Lines

    private var guideLines: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let midY = geo.size.height / 2
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: midY)); p.addLine(to: CGPoint(x: geo.size.width, y: midY)) }
                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                Path { p in p.move(to: CGPoint(x: midX, y: 0)); p.addLine(to: CGPoint(x: midX, y: geo.size.height)) }
                    .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            }
        }
    }

    // MARK: - Control Sections

    private var cropSection: some View {
        Group {
            Text("Crop")
                .font(.subheadline.bold())

            if isCropped {
                HStack {
                    Button("Undo Crop") {
                        isCropped = false
                        cropRect = nil
                        scheduleUpdate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text("Crop applied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Button("Crop") {
                        applyCrop()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(cropRect == nil)

                    Text(cropRect == nil ? "Drag on the image to select a region" : "Adjust handles, then click Crop")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                        .onChange(of: rotation) { if isCropped { scheduleUpdate() } }
                    Text(String(format: "%.1f\u{00B0}", rotation))
                        .frame(width: 45, alignment: .trailing)
                        .monospacedDigit()
                }
                Text("Guide lines appear to help align content")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button("-90\u{00B0}") { rotation = max(-180, rotation - 90); if isCropped { scheduleUpdate() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("-1\u{00B0}") { rotation = max(-180, rotation - 1); if isCropped { scheduleUpdate() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("0\u{00B0}") { rotation = 0; if isCropped { scheduleUpdate() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("+1\u{00B0}") { rotation = min(180, rotation + 1); if isCropped { scheduleUpdate() } }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("+90\u{00B0}") { rotation = min(180, rotation + 90); if isCropped { scheduleUpdate() } }
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
                        .onChange(of: threshold) { scheduleUpdate() }
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
                .onChange(of: invertExtraction) { scheduleUpdate() }
        }
    }

    private var adjustmentControls: some View {
        Group {
            Text("Adjustments")
                .font(.subheadline.bold())

            sliderRow("Brightness", value: $brightness, range: -0.5...0.5, format: "%+.0f%%", multiplier: 100)
                .onChange(of: brightness) { scheduleUpdate() }
            sliderRow("Contrast", value: $contrast, range: 0.2...3.0, format: "%.1fx", multiplier: 1)
                .onChange(of: contrast) { scheduleUpdate() }
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
                    .onChange(of: tintColor) { scheduleUpdate() }
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
            if let tiff = image.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff) {
                sourceCGImage = bmp.cgImage
            }
            cropRect = nil
            isCropped = false
            rotation = 0
            processedImage = nil
        }
    }

    // MARK: - Crop

    private func applyCrop() {
        guard let cropR = cropRect, let cg = sourceCGImage else { return }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        let pixelRect = CGRect(
            x: cropR.origin.x * w,
            y: cropR.origin.y * h,
            width: cropR.width * w,
            height: cropR.height * h
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0,
              let cropped = cg.cropping(to: pixelRect) else { return }

        sourceCGImage = cropped
        sourceImage = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        cropRect = nil
        isCropped = true
        scheduleUpdate()
    }

    // MARK: - Debounced Update

    private func scheduleUpdate() {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            updatePreview()
        }
    }

    // MARK: - Image Processing (Core Image accelerated)

    private func updatePreview() {
        guard let cg = sourceCGImage else { return }
        // Use a downscaled version for preview (max 1200px)
        let maxPreview = 1200
        let scale: CGFloat
        if cg.width > maxPreview || cg.height > maxPreview {
            scale = CGFloat(maxPreview) / CGFloat(max(cg.width, cg.height))
        } else {
            scale = 1.0
        }
        processedImage = processImage(cg, scale: scale)
    }

    private func processImage(_ cgImage: CGImage, scale: CGFloat) -> NSImage? {
        var ci = CIImage(cgImage: cgImage)

        // Scale for preview
        if scale < 1.0 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // Rotation
        if rotation != 0 {
            let radians = CGFloat(rotation) * .pi / 180.0
            ci = ci.transformed(by: CGAffineTransform(rotationAngle: radians))
            // Shift origin so the image is in positive coordinates
            ci = ci.transformed(by: CGAffineTransform(translationX: -ci.extent.origin.x, y: -ci.extent.origin.y))
        }

        // Brightness and contrast via CIColorControls (GPU-accelerated)
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ci
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = 1.0
        guard let adjusted = colorControls.outputImage else { return nil }

        // Render the adjusted image to get pixels for threshold/tint
        let extent = adjusted.extent
        let w = Int(extent.width)
        let h = Int(extent.height)
        guard w > 0, h > 0 else { return nil }

        guard let output = Self.ciContext.createCGImage(adjusted, from: extent) else { return nil }

        // Apply threshold + tint using pixel buffer
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(output, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)

        let nsColor = NSColor(tintColor).usingColorSpace(.sRGB) ?? NSColor(tintColor)
        let tR = UInt8(clamping: Int(nsColor.redComponent * 255))
        let tG = UInt8(clamping: Int(nsColor.greenComponent * 255))
        let tB = UInt8(clamping: Int(nsColor.blueComponent * 255))
        let threshF = Float(threshold)
        let inv = invertExtraction
        let count = w * h

        // Process in bulk — this loop is simple arithmetic, very fast on modern CPUs
        for i in 0..<count {
            let o = i &* 4
            let a = pixels[o + 3]
            if a < 3 { // transparent (from rotation)
                pixels[o] = 0; pixels[o+1] = 0; pixels[o+2] = 0; pixels[o+3] = 0
                continue
            }

            let r = Float(pixels[o]) / 255.0
            let g = Float(pixels[o+1]) / 255.0
            let b = Float(pixels[o+2]) / 255.0
            let lum = 0.299 * r + 0.587 * g + 0.114 * b

            let fg = inv ? (lum > threshF) : (lum < threshF)

            if fg {
                let dist = inv
                    ? (lum - threshF) / (1.0 - threshF + 0.001)
                    : (threshF - lum) / (threshF + 0.001)
                let alpha = min(1.0, max(0.0, dist * 2.0))
                pixels[o] = tR; pixels[o+1] = tG; pixels[o+2] = tB
                pixels[o+3] = UInt8(alpha * 255)
            } else {
                pixels[o] = 0; pixels[o+1] = 0; pixels[o+2] = 0; pixels[o+3] = 0
            }
        }

        guard let finalCG = ctx.makeImage() else { return nil }
        return NSImage(cgImage: finalCG, size: NSSize(width: w, height: h))
    }

    // MARK: - Add to Library

    private func addToLibrary() {
        guard let cg = sourceCGImage else { return }
        // Process at full resolution for export
        guard let fullRes = processImage(cg, scale: 1.0) else { return }
        guard let tiffData = fullRes.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
        onExtracted(pngData)
        dismiss()
    }
}

// MARK: - Crop Overlay View

private struct CropOverlayView: View {
    let image: NSImage
    @Binding var cropRect: CGRect? // normalized 0...1
    var rotation: Double

    @State private var dragStart: CGPoint?
    @State private var activeHandle: CropHandle?

    private let handleSize: CGFloat = 10

    enum CropHandle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case move
    }

    var body: some View {
        GeometryReader { geo in
            let imageSize = image.size
            let viewSize = geo.size
            let fitted = fitRect(imageSize: imageSize, viewSize: viewSize)

            ZStack {
                // Image
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(rotation))

                // Crop overlay
                if let crop = cropRect {
                    let rect = denormalize(crop, in: fitted)

                    // Dimming outside crop
                    CropDimmingOverlay(cropRect: rect, bounds: fitted)

                    // Crop border
                    Rectangle()
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.5), radius: 1)

                    // Rule of thirds
                    ruleOfThirds(rect)

                    // Handles
                    ForEach(handlePositions(rect), id: \.handle) { hp in
                        Circle()
                            .fill(.white)
                            .frame(width: handleSize, height: handleSize)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .position(hp.point)
                    }
                }
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onDrag(value: value, fitted: fitted)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        activeHandle = nil
                    }
            )
        }
    }

    private func ruleOfThirds(_ rect: CGRect) -> some View {
        ZStack {
            ForEach(1..<3, id: \.self) { i in
                let y = rect.minY + rect.height * CGFloat(i) / 3
                Path { p in p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y)) }
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                let x = rect.minX + rect.width * CGFloat(i) / 3
                Path { p in p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY)) }
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            }
        }
    }

    private struct HandlePosition: Identifiable {
        var id: String { "\(handle)" }
        let handle: CropHandle
        let point: CGPoint
    }

    private func handlePositions(_ rect: CGRect) -> [HandlePosition] {
        [
            HandlePosition(handle: .topLeft, point: CGPoint(x: rect.minX, y: rect.minY)),
            HandlePosition(handle: .topRight, point: CGPoint(x: rect.maxX, y: rect.minY)),
            HandlePosition(handle: .bottomLeft, point: CGPoint(x: rect.minX, y: rect.maxY)),
            HandlePosition(handle: .bottomRight, point: CGPoint(x: rect.maxX, y: rect.maxY)),
            HandlePosition(handle: .top, point: CGPoint(x: rect.midX, y: rect.minY)),
            HandlePosition(handle: .bottom, point: CGPoint(x: rect.midX, y: rect.maxY)),
            HandlePosition(handle: .left, point: CGPoint(x: rect.minX, y: rect.midY)),
            HandlePosition(handle: .right, point: CGPoint(x: rect.maxX, y: rect.midY)),
        ]
    }

    // MARK: - Drag Handling

    private func onDrag(value: DragGesture.Value, fitted: CGRect) {
        let loc = value.location

        if dragStart == nil {
            dragStart = value.startLocation

            // Check if starting on a handle or inside crop
            if let crop = cropRect {
                let rect = denormalize(crop, in: fitted)
                activeHandle = hitTestHandle(value.startLocation, rect: rect)
                    ?? (rect.contains(value.startLocation) ? .move : nil)
            }

            if activeHandle == nil {
                // Start new crop
                let start = clampToFitted(value.startLocation, fitted: fitted)
                let norm = normalize(CGRect(origin: start, size: .zero), in: fitted)
                cropRect = norm
                activeHandle = .bottomRight
            }
        }

        guard let handle = activeHandle else { return }
        let clamped = clampToFitted(loc, fitted: fitted)

        guard var crop = cropRect else { return }
        var rect = denormalize(crop, in: fitted)

        switch handle {
        case .topLeft:
            rect = CGRect(x: clamped.x, y: clamped.y, width: rect.maxX - clamped.x, height: rect.maxY - clamped.y)
        case .topRight:
            rect = CGRect(x: rect.minX, y: clamped.y, width: clamped.x - rect.minX, height: rect.maxY - clamped.y)
        case .bottomLeft:
            rect = CGRect(x: clamped.x, y: rect.minY, width: rect.maxX - clamped.x, height: clamped.y - rect.minY)
        case .bottomRight:
            rect = CGRect(x: rect.minX, y: rect.minY, width: clamped.x - rect.minX, height: clamped.y - rect.minY)
        case .top:
            rect = CGRect(x: rect.minX, y: clamped.y, width: rect.width, height: rect.maxY - clamped.y)
        case .bottom:
            rect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: clamped.y - rect.minY)
        case .left:
            rect = CGRect(x: clamped.x, y: rect.minY, width: rect.maxX - clamped.x, height: rect.height)
        case .right:
            rect = CGRect(x: rect.minX, y: rect.minY, width: clamped.x - rect.minX, height: rect.height)
        case .move:
            let dx = loc.x - (dragStart?.x ?? loc.x)
            let dy = loc.y - (dragStart?.y ?? loc.y)
            var moved = rect.offsetBy(dx: dx, dy: dy)
            // Clamp to fitted area
            moved.origin.x = max(fitted.minX, min(fitted.maxX - moved.width, moved.origin.x))
            moved.origin.y = max(fitted.minY, min(fitted.maxY - moved.height, moved.origin.y))
            rect = moved
            dragStart = loc
        }

        // Normalize (handle negative width/height from inverted drag)
        crop = normalize(rect.standardized, in: fitted)
        crop = CGRect(
            x: max(0, min(1, crop.origin.x)),
            y: max(0, min(1, crop.origin.y)),
            width: max(0.01, min(1 - crop.origin.x, crop.width)),
            height: max(0.01, min(1 - crop.origin.y, crop.height))
        )
        cropRect = crop
    }

    private func hitTestHandle(_ point: CGPoint, rect: CGRect) -> CropHandle? {
        let margin: CGFloat = 12
        for hp in handlePositions(rect) {
            if abs(point.x - hp.point.x) < margin && abs(point.y - hp.point.y) < margin {
                return hp.handle
            }
        }
        return nil
    }

    // MARK: - Coordinate Helpers

    private func fitRect(imageSize: NSSize, viewSize: CGSize) -> CGRect {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(
            x: (viewSize.width - w) / 2,
            y: (viewSize.height - h) / 2,
            width: w,
            height: h
        )
    }

    private func normalize(_ rect: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(
            x: (rect.origin.x - fitted.origin.x) / fitted.width,
            y: (rect.origin.y - fitted.origin.y) / fitted.height,
            width: rect.width / fitted.width,
            height: rect.height / fitted.height
        )
    }

    private func denormalize(_ norm: CGRect, in fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.origin.x + norm.origin.x * fitted.width,
            y: fitted.origin.y + norm.origin.y * fitted.height,
            width: norm.width * fitted.width,
            height: norm.height * fitted.height
        )
    }

    private func clampToFitted(_ point: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: max(fitted.minX, min(fitted.maxX, point.x)),
            y: max(fitted.minY, min(fitted.maxY, point.y))
        )
    }
}

// MARK: - Crop Dimming Overlay

private struct CropDimmingOverlay: View {
    let cropRect: CGRect
    let bounds: CGRect

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.addRect(bounds)
            path.addRect(cropRect)
            context.fill(path, with: .color(.black.opacity(0.4)), style: FillStyle(eoFill: true))
        }
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
