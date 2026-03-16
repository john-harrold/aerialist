import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct CollectionEditorView: View {
    let fileURL: URL
    @State private var model = CollectionModel()
    @State private var isExporting = false
    @State private var hasUnsavedChanges = false
    @State private var undoState = CollectionUndoState()
    @State private var selection = Set<UUID>()
    @State private var editingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button {
                    addFiles()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }

                Spacer()

                Button {
                    undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!undoState.canUndo)

                Button {
                    redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!undoState.canRedo)

                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(!hasUnsavedChanges)
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    exportAsPDF()
                } label: {
                    Label("Export as PDF", systemImage: "arrow.up.doc")
                }
                .disabled(model.entries.isEmpty || isExporting)
            }
            .padding()

            Divider()

            if model.entries.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle(fileURL.deletingPathExtension().lastPathComponent)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportAsPDF)) { _ in
            exportAsPDF()
        }
        .focusedSceneValue(\.isCollection, true)
    }

    // MARK: - Undo Support

    private func updateModel(_ newModel: CollectionModel, actionName: String) {
        let oldModel = model
        undoState.push(oldModel)
        model = newModel
        hasUnsavedChanges = true
    }

    private func undo() {
        guard let previous = undoState.undo(current: model) else { return }
        model = previous
        hasUnsavedChanges = true
    }

    private func redo() {
        guard let next = undoState.redo(current: model) else { return }
        model = next
        hasUnsavedChanges = true
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Drop files here or click Add Files")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("PDF, DOCX, PNG, JPG, TIFF, BMP, GIF")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File List

    private var fileList: some View {
        List(selection: $selection) {
            ForEach(model.entries) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.iconName)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        if editingID == entry.id {
                            RenameField(
                                text: bindingForTitle(entry.id),
                                onCommit: { editingID = nil },
                                onCancel: { editingID = nil }
                            )
                            .font(.body.weight(.medium))
                        } else {
                            Text(entry.tocTitle)
                                .font(.body.weight(.medium))
                        }
                        Text(entry.fileName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        openEntry(entry)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Spindrift")

                    Button {
                        removeEntry(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
                .padding(.vertical, 4)
                .tag(entry.id)
            }
            .onMove { from, to in
                moveEntries(from: from, to: to)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1 {
                    Button("Rename") {
                        editingID = ids.first
                    }
                }
                Button("Open \(ids.count == 1 ? "File" : "\(ids.count) Files")") {
                    for id in ids {
                        if let entry = model.entries.first(where: { $0.id == id }) {
                            openEntry(entry)
                        }
                    }
                }
                Button("Remove \(ids.count == 1 ? "File" : "\(ids.count) Files")") {
                    removeEntries(ids)
                }
            }
        }
        .onDeleteCommand {
            if !selection.isEmpty {
                removeEntries(selection)
            }
        }
        .onKeyPress(.return) {
            if editingID == nil, selection.count == 1 {
                editingID = selection.first
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if editingID != nil {
                editingID = nil
                return .handled
            }
            return .ignored
        }
    }

    private func bindingForTitle(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                model.entries.first { $0.id == id }?.tocTitle ?? ""
            },
            set: { newValue in
                guard let index = model.entries.firstIndex(where: { $0.id == id }) else { return }
                let oldTitle = model.entries[index].tocTitle
                guard newValue != oldTitle else { return }
                var newModel = model
                newModel.entries[index].tocTitle = newValue
                updateModel(newModel, actionName: "Rename")
            }
        )
    }

    // MARK: - File I/O

    private func load() {
        // Support both legacy package format and flat file
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        let data: Data?
        if isDir.boolValue {
            data = try? Data(contentsOf: fileURL.appendingPathComponent("collection.json"))
        } else {
            data = try? Data(contentsOf: fileURL)
        }
        guard let data,
              let loaded = try? JSONDecoder().decode(CollectionModel.self, from: data) else {
            return
        }
        model = loaded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(model) else { return }

        // If the existing file is a package directory, migrate to flat file
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            try? FileManager.default.removeItem(at: fileURL)
        }

        try? data.write(to: fileURL, options: .atomic)
        hasUnsavedChanges = false
    }

    // MARK: - Actions

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .bmp, .gif,
                                     UTType("org.openxmlformats.wordprocessingml.document")!,
                                     UTType("com.microsoft.word.doc")!]
        panel.begin { response in
            guard response == .OK else { return }
            addURLs(panel.urls)
        }
    }

    private func addURLs(_ urls: [URL]) {
        var newModel = model
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let entry = try? CollectionEntry(url: url) else { continue }
            newModel.entries.append(entry)
        }
        guard newModel.entries.count != model.entries.count else { return }
        updateModel(newModel, actionName: "Add Files")
    }

    private func openEntry(_ entry: CollectionEntry) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpindriftPreview")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent(entry.originalFileName)
        try? entry.fileData.write(to: tempURL)
        NSDocumentController.shared.openDocument(
            withContentsOf: tempURL,
            display: true
        ) { _, _, _ in }
    }

    private func removeEntry(_ id: UUID) {
        removeEntries([id])
    }

    private func removeEntries(_ ids: Set<UUID>) {
        var newModel = model
        newModel.entries.removeAll { ids.contains($0.id) }
        updateModel(newModel, actionName: ids.count == 1 ? "Remove File" : "Remove Files")
        selection.subtract(ids)
    }

    private func moveEntries(from: IndexSet, to: Int) {
        var newModel = model
        newModel.entries.move(fromOffsets: from, toOffset: to)
        updateModel(newModel, actionName: "Reorder")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        addURLs([url])
                    }
                }
            }
        }
        return handled
    }

    private func exportAsPDF() {
        let entries = model.entries
        guard !entries.isEmpty else { return }
        isExporting = true

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var filePairs: [(url: URL, label: String)] = []
        for entry in entries {
            let tempURL = tempDir.appendingPathComponent(entry.originalFileName)
            guard (try? entry.fileData.write(to: tempURL)) != nil else { continue }
            filePairs.append((url: tempURL, label: entry.tocTitle))
        }

        guard let combined = FileCombinerService.combineWithLabels(files: filePairs),
              let pdfData = combined.dataRepresentation() else {
            try? FileManager.default.removeItem(at: tempDir)
            isExporting = false
            return
        }

        try? FileManager.default.removeItem(at: tempDir)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Combined.pdf"
        savePanel.begin { response in
            isExporting = false
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try pdfData.write(to: url)
                NSWorkspace.shared.open(url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

}

/// A TextField that auto-focuses when it appears and handles Enter/Escape.
private struct RenameField: View {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("TOC Title", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
            .onAppear {
                isFocused = true
            }
    }
}

/// Simple stack-based undo/redo for collection models.
struct CollectionUndoState {
    private var undoStack: [CollectionModel] = []
    private var redoStack: [CollectionModel] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func push(_ model: CollectionModel) {
        undoStack.append(model)
        redoStack.removeAll()
    }

    mutating func undo(current: CollectionModel) -> CollectionModel? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: CollectionModel) -> CollectionModel? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
