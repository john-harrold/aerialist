# Aerialist — Application Specification

Aerialist is a native macOS PDF reading and annotation tool built as an alternative to Adobe Acrobat, focusing on a specific subset of PDF editing features. This document defines the complete application as implemented.

## Technology Stack

- **Platform**: macOS 14.0+ (Sonnet), native Mac application
- **Language**: Swift 6 (strict concurrency)
- **UI Framework**: SwiftUI + AppKit hybrid
- **PDF Engine**: PDFKit (`PDFDocument`, `PDFView`, `PDFAnnotation` subclasses)
- **OCR**: Apple Vision framework (`VNRecognizeTextRequest`)
- **Architecture**: MVVM — `DocumentViewModel` (@Observable, @MainActor) drives the UI; `AerialistDocument` (ReferenceFileDocument) handles persistence
- **Concurrency**: `@MainActor` on all view models, services touching PDFKit; `@unchecked Sendable` on `AerialistDocument` for `ReferenceFileDocument` conformance; custom `registerUndo` helper dispatching `@MainActor` closures via `Task`

## Application Structure

### App Entry Point
- `AerialistApp.swift`: `@main` SwiftUI `App` using `DocumentGroup` for document-based multi-window support. Each window opens one PDF. File menu includes "Export as PDF..." (Cmd+Shift+E) via `NotificationCenter`.

### Document Layer

#### `AerialistDocument.swift` — ReferenceFileDocument
- Opens and saves plain `.pdf` files (no custom package format)
- **Sidecar persistence**: Annotation data is stored as a hidden `.freeText` annotation on page 0 with `userName = "com.aerialist.sidecar"`, `bounds = 0.1x0.1`, `color = clear`, containing the sidecar JSON in `contents`
- **Annotation tagging**: All managed annotations get `userName = "aerialist:type:UUID"` (e.g., `"aerialist:comment:550E8400-..."`) so they can be identified, reconciled, and stripped on load
- **Reconciliation on load** (`reconcileAndStrip`): When opening a file, scans all pages for tagged annotations. Reads back property changes made by external apps (e.g., Preview.app moved a comment or edited text). Updates the sidecar model accordingly. If a tagged annotation is missing (sidecar version >= 2), it was deleted externally — removes from sidecar. Strips all managed annotations from pages so the coordinator can recreate them fresh.
- **Standard annotation save**: On `snapshot()`, temporarily swaps custom `PDFAnnotation` subclasses with standard PDF types (`.freeText`, `.square`, `.circle`, `.line`, `.text`, `.stamp`, `.highlight`, `.underline`, `.strikeOut`) so other PDF readers can display them. After serialization, restores custom annotations for continued editing.
- Sidecar version 2 enables deletion detection

#### `SidecarModel.swift` — Codable Annotation Models
Root model containing all annotation arrays:
```
SidecarModel {
    version: Int (default 2)
    sourceFileHash: String
    stamps: [StampAnnotationModel]
    textBoxes: [TextBoxAnnotationModel]
    comments: [CommentAnnotationModel]
    markups: [MarkupAnnotationModel]
    shapes: [ShapeAnnotationModel]
    ocrResults: [String: OCRPageResult]    // keyed by page index string
    formFieldOverrides: [String: String]
}
```

**Annotation Models:**

- **StampAnnotationModel**: `id`, `pageIndex`, `bounds`, `imageData` (base64 PNG), `opacity`, `rotation` (degrees). Custom decoder for backward-compatible `rotation` field.
- **TextBoxAnnotationModel**: `id`, `pageIndex`, `bounds`, `text` (default "Text"), `fontName` (default "Helvetica"), `fontSize` (default 14), `color` (hex), `backgroundColor` (hex, optional), `outlineColor` (hex, optional), `outlineStyle` (OutlineStyle enum)
- **CommentAnnotationModel**: `id`, `pageIndex`, `bounds`, `text`, `author` (NSFullUserName), `date`
- **MarkupAnnotationModel**: `id`, `pageIndex`, `type` (MarkupType: highlight/underline/strikeOut), `quadrilateralPoints` (array of 4-point quads), `color` (hex)
- **ShapeAnnotationModel**: `id`, `pageIndex`, `bounds`, `shapeType` (line/arrow/rectangle/ellipse), `strokeColor` (hex), `fillColor` (hex, optional), `strokeWidth`, `strokeStyle` (OutlineStyle), `rotation` (degrees), `lineStart`/`lineEnd` (QuadPoint, optional — for line/arrow endpoints)

**Supporting Types:**
- `AnnotationBounds`: x, y, width, height — converts to/from CGRect
- `QuadPoint`: x, y — used for markup quad points and line endpoints
- `OutlineStyle`: none/solid/dashed/dotted (CaseIterable enum)
- `ShapeType`: line/arrow/rectangle/ellipse (CaseIterable enum with systemImage and tooltip)
- `OCRLineResult`: text, boundingBox, confidence
- `OCRPageResult`: array of OCRLineResult

#### `SidecarIO.swift`
JSON encode/decode utilities for SidecarModel.

#### `DocumentExporter.swift`
Exports a flattened PDF with all sidecar annotations rendered as standard PDF annotations. Includes `ImageStampAnnotation` helper for stamp rendering. Contains `NSColor` hex extension used throughout the app.

### PDF Canvas Layer

#### `AerialistPDFView.swift` — Custom PDFView Subclass
- Overrides `mouseDown`, `mouseDragged`, `mouseUp`, `rightMouseDown` for custom interaction
- Callbacks: `onPageClick`, `onPageDoubleClick`, `onPageDrag`, `onPageMouseUp`, `onPageRightClick`
- Tracks `isDragging` state to only forward drags when the initial click was consumed
- Converts mouse coordinates from view space to PDF page coordinates

#### `PDFCanvasView.swift` — NSViewRepresentable
- Wraps `AerialistPDFView` for SwiftUI integration
- `makeNSView`: Creates the PDF view, wires callbacks to coordinator, sets auto-scales
- `updateNSView`: Navigates to correct page via `pdfView.go(to:)`, syncs annotations via revision tracking, applies markup tool changes, sets initial zoom-to-width

#### `PDFCanvasCoordinator.swift` — Central Interaction Controller
Manages all PDF canvas interactions:

**Click Handling** (`handlePageClick`):
- Each tool mode (select, stamp, textBox, comment, draw, markup, removeMarkup) has its own hit-test-first logic
- Clicks on existing annotations select them and set up drag targets
- `handleCrossTypeHit` handles clicking an annotation of a different type than the current tool mode — switches tool mode and selects
- Clicks on empty space create new annotations (text box, comment) or place stamps

**Double-Click** (`handlePageDoubleClick`):
- On text boxes: begins inline text editing with an NSTextView overlay

**Inline Text Editing**:
- Creates NSScrollView + NSTextView overlay positioned over the text box in PDFView coordinates
- Matches font, size, color scaled by PDFView scale factor
- Auto-commits on page change or zoom change (observers)
- Commit writes text back to sidecar, registers undo
- Escape cancels and restores pre-edit state

**Drag Handling** (`handlePageDrag`):
- `DragTarget` enum: comment, stamp, stampResize, stampRotate, textBox, textBoxResize, shape, shapeResize, shapeRotate, lineEndpointStart, lineEndpointEnd
- Shape creation: live resize via `updateLiveShapeBounds`/`updateLiveLineEndpoints` for responsiveness
- `resizedBounds()`: Handles all 8 resize handles (4 corners + 4 midpoints). Optional `aspectRatio` parameter for shift-constrained resize (stamps use original image ratio, shapes use 1:1)
- Rotation: computes angle from center to mouse via `atan2`

**Mouse Up** (`handlePageMouseUp`):
- Finalizes shape creation (writes live bounds to sidecar, removes if too small)
- Finalizes shape move/resize (writes back from live annotation)
- Registers undo for the full drag operation

**Delete** (`handleDeleteKey`):
- If annotation selected: deletes it, selects last remaining sibling of same type
- If no annotation: triggers page deletion with confirmation dialog

**Right-Click** (`handlePageRightClick`):
- Context menu with "Delete [Type]" for any annotation

**Annotation Sync** (`syncAnnotations`):
- Revision-based — only syncs when `annotationRevision` changes
- Separate sync methods for each type: stamps, textBoxes, comments, markups, shapes
- Creates/updates/removes live `PDFAnnotation` subclass instances on PDF pages
- Remove/re-add cycle forces PDFKit to redraw (it caches annotation rendering)

**Markup Tools** (`handleTextSelectionComplete`, `applyMarkup`):
- Captures native PDFView text selection
- Creates MarkupAnnotationModel with quad points from selection lines
- Supports highlight (with color choice), underline, strikethrough

#### Custom PDFAnnotation Subclasses

**StampAnnotation**: Draws image with opacity and rotation. Selection UI: 8 resize handles (white circles with blue border) + rotation handle (dashed blue line to green circle 20pt above). `color = .clear` to preserve transparency. Expanded bounds to prevent clipping during rotation.

**TextBoxAnnotation**: Draws background fill, outline (solid/dashed/dotted), selection border, and text with proper PDF coordinate transforms. `update()` method for syncing properties. `isEditingInline_` flag suppresses text drawing when NSTextView overlay is active.

**CommentAnnotation**: Renders comment icon (yellow note). Blue selection ring + subtle fill when selected.

**ShapeAnnotation**: Draws rectangle/ellipse (with rotation, fill, stroke) or line/arrow (with endpoints). Selection UI: 8 resize handles for shapes, endpoint handles for lines. Rotation handle for rect/ellipse. Stroke styles: solid, dashed (6,3), dotted (1.5,3). Expanded bounds accommodate stroke width and rotation handle.

**StrikeOutAnnotation**: Custom strikethrough rendering (PDFKit's built-in `.strikeOut` is unreliable on some macOS versions). Draws red lines through each quad's vertical center.

#### `InteractionHandler.swift` — Hit Testing
- Static hit-test against all sidecar annotations on a page
- Returns `HitResult`: none, stamp(id, action), textBox(id, action), comment(id), shape(id, action)
- `StampAction` enum: drag, resize (8 handles), dragLineStart/End, rotate
- Tests in order: comments (small, on top) → text boxes → shapes → stamps
- Rotation handle hit-testing for stamps and non-line shapes
- Line/arrow hit-testing: endpoint proximity, then perpendicular distance to segment
- `resizeMargin`: 12pt hit area around handles

### View Models

#### `DocumentViewModel.swift` — Main ViewModel
`@MainActor @Observable` class with:
- **Tool state**: `toolMode` (ToolMode enum), `highlightColor`, draw defaults (shapeType, strokeColor, fillColor, hasFill, strokeWidth, strokeStyle)
- **Navigation**: `currentPageIndex`, `goToPage/Next/Previous`
- **Selection**: `selectedAnnotationID`, `selectedPageIndices` (for multi-page selection in thumbnail sidebar)
- **Stamp library**: `stampLibrary` (lazy), `pendingStampData`, `selectedStampLibraryID`, `showStampPicker`
- **Page management**: `deletePages(at:)` handles multi-page deletion (removes from highest index first, maps annotation indices, re-keys OCR), `confirmDeletePages(_:)` shows confirmation, `executePendingPageDeletion()`
- **Sidecar**: Setter triggers `document?.sidecar` update + `annotationRevision` increment
- **Undo**: `registerUndo` wraps `UndoManager.registerUndo` with `@MainActor Task` dispatch
- **Combine**: `showCombineSheet`, `applyCombinedDocument`

**ToolMode enum**: select, stamp, textBox, comment, draw, highlight, underline, strikethrough, removeMarkup. Grouped into `pickerCases` (main segmented picker) and `markupCases` (markup toolbar).

**HighlightColor**: Yellow, Green, Blue, Pink, Purple — each with hex and SwiftUI Color.

#### Extension ViewModels
- `StampToolViewModel.swift`: `addStamp(imageData:)` — decodes image, preserves aspect ratio (longest edge = 150pt), creates StampAnnotationModel with base64 data. `moveStamp`, `deleteStamp`.
- `TextEditingViewModel.swift`: Text box CRUD operations
- `FormFillingViewModel.swift`: Form field override operations
- `OCRViewModel.swift`: OCR trigger and result storage
- `CombineViewModel.swift`: File combining orchestration

### Views

#### `ContentView.swift` — Main Layout
```
NavigationSplitView {
    ThumbnailSidebar (collapsible, 120-250pt wide)
} detail: {
    VStack {
        StampToolbar (when stamp mode)
        MarkupToolbar (when markup mode)
        DrawToolbar (when draw mode)
        PDFCanvasView
            .overlay(toolModeHint)
    }
}
.inspector(inspectorContent, 220-300pt wide)
.toolbar(MainToolbar)
.sheet(StampPickerSheet)
.sheet(CombineFilesSheet)
.confirmationDialog(deletePageConfirmation)
```

**Inspector content** (right panel): Shows contextual inspector based on tool mode and selection:
- Comment mode or comment selected → CommentsPanel
- TextBox mode or textBox selected → TextBoxesPanel
- Shape selected → ShapeInspector
- Draw mode (no selection) → "Click and drag" hint
- Stamp selected → StampInspector
- Otherwise → "Select an annotation" hint

**Tool mode hints** (top-left overlay on canvas):
- Stamp: "Click to place stamp" or "Select a stamp from the toolbar above"
- Comment: "Click to place comment"
- Draw: "Click and drag to draw [shape type]"
- Markup: "Select text to [highlight/underline/strikethrough]"
- Remove: "Click on markup to remove"

#### Toolbars

**MainToolbar**: Segmented picker for main tools (Select, Stamp, Text Box, Comment, Draw) + Markup toggle button. Custom binding deselects markup when a main tool is picked.

**StampToolbar** (`StampLibraryPopover.swift` → `StampToolbar`): Horizontal scrollable strip of 32x32 stamp thumbnails from the persistent stamp library. Selected stamp highlighted with accent color. "Add Stamp..." button opens NSOpenPanel for `.png`/`.pdf`. Context menu "Delete" on each stamp. Clicking a stamp stores its data in `pendingStampData` for repeated placement.

**Markup Toolbar**: Highlight/Underline/Strikethrough/Remove buttons + color picker row (5 colors) when highlight is active.

**Draw Toolbar**: Shape type picker (Line, Arrow, Rectangle, Ellipse) + stroke width field + stepper + line style picker (None/Solid/Dashed/Dotted) + stroke color picker + fill toggle and fill color (for rect/ellipse only).

#### Sidebar

**ThumbnailSidebar**: ScrollView with LazyVStack of page thumbnails (120x160). Multi-page selection:
- Plain click: navigates to page, clears multi-select
- Cmd-click: toggles page in selection
- Shift-click: range-selects from last clicked
- Visual state: accent-color border and blue overlay on selected pages
- Context menu: "Delete Page" / "Delete N Pages" with confirmation dialog routing

#### Inspectors

**CommentsPanel**: List of all comments sorted by page then date. Selected comment highlighted, auto-scrolled to. Inline text editing for selected comment. Right-click delete. Empty state when no comments exist.

**TextBoxesPanel**: List of all text boxes with selected one highlighted. Properties form: text field, font picker, font size, text color, background (None/Color + ColorPicker), outline style (None/Solid/Dashed/Dotted + ColorPicker when not None).

**ShapeInspector**: Form with shape type picker, stroke width, line style, line color, fill toggle + fill color (rect/ellipse), rotation slider 0-360 (rect/ellipse), position info, delete button.

**StampInspector**: Opacity slider, rotation slider 0-360, position/size info, delete button (selects last remaining stamp on delete).

#### Sheets

**StampPickerSheet**: NSOpenPanel for browsing PNG files (legacy fallback, replaced by stamp toolbar).

**CombineFilesSheet**: File list with drag-to-reorder, add files (PDF, PNG, JPEG, TIFF, BMP, GIF), remove individual files, Combine button. Uses `FileCombinerService`.

**OCRProgressSheet**: Progress indicator during OCR processing.

### Model Layer

#### `StampLibrary.swift` — Persistent Stamp Collection
- Stores stamps in `~/Library/Application Support/com.aerialist.app/stamps/` as PNG files with UUID filenames
- `stamps.json` index file with metadata (id, name, filename, dateAdded)
- `@Observable` class: `load()`, `addStamp(imageData:name:)`, `addStamp(from:url:)`, `deleteStamp(id:)`, `imageData(for:)`, `thumbnail(for:)`
- Accepts PNG and PDF files. PDFs rendered to PNG via `CGContext` at 2x scale with transparent background
- PNG pipeline uses `CGImageSource` → `CGImageDestination` (ImageIO) for alpha channel preservation — avoids TIFF roundtrip

### Services

**OCRService**: Renders PDF page to CGImage at 300 DPI, runs Vision `VNRecognizeTextRequest` (accurate mode with language correction), converts normalized Vision coordinates to PDF page coordinates. `recognizeAllPages` with progress callback.

**FileCombinerService**: Combines multiple files (PDFs and images) into a single PDFDocument. Creates PDF outline (bookmarks) with filename labels for each source file.

**ImageToPDFService**: Converts image files to PDFPage objects for combining.

**ExportService**: Export utilities.

## Key Design Patterns

### Annotation Lifecycle
1. **Creation**: User action → model appended to sidecar → `annotationRevision` increments → `PDFCanvasView.updateNSView` fires → coordinator `syncAnnotations()` creates live `PDFAnnotation` subclass on the page
2. **Editing**: User drags/types → sidecar model updated → sync cycle updates live annotation properties → remove/re-add forces PDFKit redraw
3. **Persistence**: On save → sidecar JSON embedded as hidden annotation → custom annotations swapped with standard types → PDF serialized → originals restored
4. **Load**: PDF opened → sidecar extracted → tagged annotations reconciled (captures external edits) → all managed annotations stripped → coordinator recreates fresh

### Undo/Redo
- All modifications capture `oldSidecar` before changes
- `registerUndo` dispatches restoration via `Task { @MainActor in ... }`
- Undo restores the full sidecar snapshot, which triggers annotation re-sync

### Hit Testing and Interaction
- `InteractionHandler` provides unified hit-testing across all annotation types
- Each tool mode's click handler: hit-test first → if hit, select + set up drag → if miss, create new or deselect
- Cross-type hits switch tool mode automatically (e.g., clicking a comment while in draw mode switches to comment mode)

### Page Management
- Multi-page selection tracked in `selectedPageIndices`
- Deletion removes pages from highest index first to avoid index shifting
- Sidecar cleanup: removes annotations on deleted pages, maps indices for surviving pages using `newIndex(for:)`, re-keys OCR results
- Undo re-inserts pages and restores full sidecar

## File Structure
```
Aerialist/
├── App/
│   └── AerialistApp.swift
├── Document/
│   ├── AerialistDocument.swift
│   ├── DocumentExporter.swift
│   ├── SidecarIO.swift
│   └── SidecarModel.swift
├── Model/
│   ├── MarkupAnnotationModel+Extensions.swift
│   ├── StampAnnotationModel+Extensions.swift
│   └── StampLibrary.swift
├── PDFCanvas/
│   ├── AerialistPDFView.swift
│   ├── CommentAnnotation.swift
│   ├── InteractionHandler.swift
│   ├── PDFCanvasCoordinator.swift
│   ├── PDFCanvasView.swift
│   ├── ShapeAnnotation.swift
│   ├── StampAnnotation.swift
│   ├── StrikeOutAnnotation.swift
│   └── TextBoxAnnotation.swift
├── Services/
│   ├── ExportService.swift
│   ├── FileCombinerService.swift
│   ├── ImageToPDFService.swift
│   └── OCRService.swift
├── ViewModels/
│   ├── CombineViewModel.swift
│   ├── DocumentViewModel.swift
│   ├── FormFillingViewModel.swift
│   ├── OCRViewModel.swift
│   ├── StampToolViewModel.swift
│   └── TextEditingViewModel.swift
└── Views/
    ├── ContentView.swift
    ├── Inspectors/
    │   ├── CommentInspector.swift
    │   ├── CommentsPanel.swift
    │   ├── FormFieldInspector.swift
    │   ├── ShapeInspector.swift
    │   ├── StampInspector.swift
    │   ├── TextBoxesPanel.swift
    │   └── TextInspector.swift
    ├── Sheets/
    │   ├── CombineFilesSheet.swift
    │   ├── OCRProgressSheet.swift
    │   └── StampPickerSheet.swift
    ├── Sidebar/
    │   ├── AnnotationListSidebar.swift
    │   ├── OutlineSidebar.swift
    │   └── ThumbnailSidebar.swift
    ├── Stamps/
    │   └── StampLibraryPopover.swift (contains StampToolbar)
    └── Toolbar/
        └── MainToolbar.swift
```

## Feature Status

### Implemented and Working
- PDF viewing with page navigation (thumbnails, scroll, keyboard)
- Transparent PNG/PDF stamp placement with persistent stamp library
- Stamp move, resize (8 handles), rotate (handle + inspector slider)
- Shift+resize maintains original image aspect ratio
- Text boxes with font, size, color, background, outline style controls
- Inline text editing (double-click text box)
- Comments with movable icons, comments panel, selection highlight
- Drawing shapes: line, arrow, rectangle, ellipse
- Shape properties: stroke color/width/style, fill, rotation (rect/ellipse)
- Text markup: highlight (5 colors), underline, strikethrough
- Remove markup tool
- Multi-page selection (Cmd-click, Shift-click) with delete confirmation
- Page deletion with undo support
- File combining (PDF + images) with bookmarks
- OCR via Apple Vision framework
- Sidecar persistence embedded in PDF
- Interoperability with Preview.app (standard annotation types, reconciliation)
- Undo/redo for all operations
- Export as flattened PDF
- Right-click context menus on all annotations
- Tool mode hints overlay

### Partially Implemented / Scaffolded
- Form field filling (model and view model exist, UI scaffolded)
- Annotation list sidebar (file exists, not fully wired)
- Outline sidebar (file exists, not fully wired)

### Not Yet Implemented
- OCR text overlay (making scanned text selectable)
- Bookmark editing UI
- Form field auto-detection
