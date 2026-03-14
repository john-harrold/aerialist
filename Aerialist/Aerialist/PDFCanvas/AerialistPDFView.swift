import PDFKit
import AppKit

/// PDFView subclass that intercepts mouse events for tool actions.
class AerialistPDFView: PDFView {
    /// Called when the user clicks on a page. Returns true if the click was consumed.
    var onPageClick: ((_ page: PDFPage, _ pagePoint: CGPoint, _ pageIndex: Int) -> Bool)?

    /// Called during a drag. Provides the current page point.
    var onPageDrag: ((_ page: PDFPage, _ pagePoint: CGPoint, _ pageIndex: Int) -> Void)?

    /// Called when the mouse is released after a drag.
    var onPageMouseUp: ((_ page: PDFPage, _ pagePoint: CGPoint, _ pageIndex: Int) -> Void)?

    /// Called on right-click. Returns an NSMenu to show, or nil.
    var onPageRightClick: ((_ page: PDFPage, _ pagePoint: CGPoint, _ pageIndex: Int) -> NSMenu?)?

    /// Called when a native text selection drag completes.
    var onTextSelectionComplete: (() -> Void)?

    /// Called when the user double-clicks on a page. Returns true if the click was consumed.
    var onPageDoubleClick: ((_ page: PDFPage, _ pagePoint: CGPoint, _ pageIndex: Int) -> Bool)?

    /// Called when the Escape key is pressed.
    var onEscapeKey: (() -> Void)?

    /// Called when the delete/backspace key is pressed.
    var onDeleteKey: (() -> Void)?

    /// Called when Cmd+C is pressed. Returns true if the copy was consumed (box selection).
    var onCopyKey: (() -> Bool)?

    /// When set, overrides the default PDFView cursor (I-beam) with the given cursor.
    var overrideCursor: NSCursor? {
        didSet {
            if overrideCursor != oldValue {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    /// Legacy convenience — crosshair maps to overrideCursor.
    var usesCrosshairCursor: Bool {
        get { overrideCursor == .crosshair }
        set { overrideCursor = newValue ? .crosshair : nil }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        if let cursor = overrideCursor {
            discardCursorRects()
            addCursorRect(visibleRect, cursor: cursor)
        } else {
            super.resetCursorRects()
        }
    }

    /// Whether we consumed the initial mouseDown (and should track drag/mouseUp)
    private var isDragging = false

    /// Local event monitor for key events (needed because PDFView's internal document view
    /// is the actual first responder, so our keyDown override never fires).
    private nonisolated(unsafe) var keyMonitor: Any?

    override func mouseDown(with event: NSEvent) {
        isDragging = false

        let viewPoint = convert(event.locationInWindow, from: nil)

        // Double-click: try inline editing before anything else
        if event.clickCount == 2,
           let onPageDoubleClick,
           let page = page(for: viewPoint, nearest: false) {
            let pagePoint = convert(viewPoint, to: page)
            let pageIndex = document?.index(for: page) ?? 0
            if onPageDoubleClick(page, pagePoint, pageIndex) {
                return // consumed — don't set isDragging
            }
        }

        if let onPageClick,
           let page = page(for: viewPoint, nearest: false) {
            let pagePoint = convert(viewPoint, to: page)
            let pageIndex = document?.index(for: page) ?? 0

            if onPageClick(page, pagePoint, pageIndex) {
                isDragging = true
                window?.makeFirstResponder(self)
                return
            }
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let page = page(for: viewPoint, nearest: true) {
                let pagePoint = convert(viewPoint, to: page)
                let pageIndex = document?.index(for: page) ?? 0
                onPageDrag?(page, pagePoint, pageIndex)
            }
        } else {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            let viewPoint = convert(event.locationInWindow, from: nil)
            if let page = page(for: viewPoint, nearest: true) {
                let pagePoint = convert(viewPoint, to: page)
                let pageIndex = document?.index(for: page) ?? 0
                onPageMouseUp?(page, pagePoint, pageIndex)
            }
        } else {
            super.mouseUp(with: event)
            // After any native PDFView mouse interaction, check if text was selected
            if currentSelection != nil {
                onTextSelectionComplete?()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                // Only handle if our window is key and the first responder is within our view hierarchy
                guard let window = self.window,
                      window.isKeyWindow,
                      let responder = window.firstResponder as? NSView,
                      responder.isDescendant(of: self) else {
                    return event
                }

                // When an NSTextView is first responder (inline editing), only
                // intercept Escape — let all other keys pass through to the text view
                if responder is NSTextView {
                    if event.keyCode == 0x35 { // Escape
                        self.onEscapeKey?()
                        return nil
                    }
                    return event
                }

                // Cmd+C (keyCode 0x08 = 'c')
                if event.keyCode == 0x08, event.modifierFlags.contains(.command) {
                    if let onCopyKey = self.onCopyKey, onCopyKey() {
                        return nil  // consumed by box selection copy
                    }
                    return event  // let native Cmd+C work
                }

                // Escape key
                if event.keyCode == 0x35 {
                    self.onEscapeKey?()
                    return nil
                }
                // Delete (forward delete) = 0x75, Backspace = 0x33
                if event.keyCode == 0x75 || event.keyCode == 0x33 {
                    self.onDeleteKey?()
                    return nil  // consume the event
                }
                return event
            }
        } else if window == nil, let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        if let onPageRightClick,
           let page = page(for: viewPoint, nearest: false) {
            let pagePoint = convert(viewPoint, to: page)
            let pageIndex = document?.index(for: page) ?? 0

            if let menu = onPageRightClick(page, pagePoint, pageIndex) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
        }
        super.rightMouseDown(with: event)
    }
}
