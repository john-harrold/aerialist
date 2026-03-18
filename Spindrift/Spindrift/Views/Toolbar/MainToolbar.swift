import SwiftUI

struct MainToolbar: CustomizableToolbarContent {
    @Bindable var viewModel: DocumentViewModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "tool-browse") {
            toolButton(for: .browse, tooltip: "Browse, search, select, and zoom")
        }

        ToolbarItem(id: "tool-stamp") {
            toolButton(for: .stamp, tooltip: "Place image stamps on the page")
        }

        ToolbarItem(id: "tool-textbox") {
            toolButton(for: .textBox, tooltip: "Add a text box")
        }

        ToolbarItem(id: "tool-comment") {
            toolButton(for: .comment, tooltip: "Add a comment")
        }

        ToolbarItem(id: "tool-draw") {
            toolButton(for: .draw, tooltip: "Draw shapes")
        }

        ToolbarItem(id: "tool-markup") {
            Button {
                viewModel.showOCRToolbar = false
                if viewModel.toolMode.isMarkup {
                    viewModel.toolMode = .browse
                } else {
                    viewModel.toolMode = .highlight
                }
            } label: {
                Label("Markup", systemImage: "highlighter")
            }
            .help("Markup: highlight, underline, strikethrough")
            .activeButtonStyle(viewModel.toolMode.isMarkup)
        }

        ToolbarItem(id: "tool-ocr") {
            Button {
                viewModel.showOCRToolbar.toggle()
                if viewModel.showOCRToolbar && viewModel.toolMode.isMarkup {
                    viewModel.toolMode = .browse
                }
                if viewModel.showOCRToolbar {
                    viewModel.showTableToolbar = false
                }
            } label: {
                Label("OCR", systemImage: "text.viewfinder")
            }
            .help("OCR — Recognize text")
            .activeButtonStyle(viewModel.showOCRToolbar)
        }

        ToolbarItem(id: "tool-table") {
            Button {
                viewModel.showTableToolbar.toggle()
                if viewModel.showTableToolbar {
                    viewModel.showOCRToolbar = false
                    if viewModel.toolMode.isMarkup {
                        viewModel.toolMode = .browse
                    }
                    viewModel.toolMode = .tableSelect
                } else {
                    if viewModel.toolMode == .tableSelect {
                        viewModel.toolMode = .browse
                    }
                    viewModel.clearTableSelection()
                }
            } label: {
                Label("Table", systemImage: "tablecells")
            }
            .help("Table selection — Extract tables")
            .activeButtonStyle(viewModel.showTableToolbar)
        }
    }

    /// Selects a main tool mode and clears OCR/table state.
    private func selectTool(_ mode: ToolMode) {
        viewModel.showOCRToolbar = false
        if viewModel.showTableToolbar {
            viewModel.showTableToolbar = false
            viewModel.clearTableSelection()
        }
        viewModel.toolMode = mode
    }

    /// Creates a toolbar button for one of the five main tool modes.
    private func toolButton(for mode: ToolMode, tooltip: String) -> some View {
        Button {
            selectTool(mode)
        } label: {
            Label(mode.rawValue, systemImage: mode.systemImage)
        }
        .help(tooltip)
        .activeButtonStyle(viewModel.toolMode == mode)
    }
}
