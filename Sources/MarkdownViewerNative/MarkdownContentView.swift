import SwiftUI
import Markdown

// Disambiguate types
typealias MarkdownText = Markdown.Text
typealias MarkdownLink = Markdown.Link
typealias MarkdownTable = Markdown.Table

// MARK: - Inline Markup -> AttributedString
//
// Inline markup (bold, italic, strikethrough, links, code) is composed into a single
// `AttributedString` per paragraph/heading/cell rather than one SwiftUI view per child.
// This does two things a naive per-child-view approach can't:
//   1. Preserves nested formatting (e.g. "**bold _italic_**") instead of flattening
//      nested spans to plain text via `.plainText`.
//   2. Lets the whole run of inline content wrap and flow as one paragraph, instead of
//      each inline child (text run, bold run, link, ...) stacking on its own line.
func buildAttributedString(from container: Markup, isDarkMode: Bool) -> AttributedString {
    var result = AttributedString()
    for child in container.children {
        result += attributedFragment(for: child, isDarkMode: isDarkMode, bold: false, italic: false, strikethrough: false)
    }
    return result
}

private func attributedFragment(
    for markup: Markup,
    isDarkMode: Bool,
    bold: Bool,
    italic: Bool,
    strikethrough: Bool
) -> AttributedString {
    let baseColor: Color = isDarkMode ? .white : .black

    func styledFont() -> Font? {
        guard bold || italic else { return nil }
        var font = Font.body
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    if let text = markup as? MarkdownText {
        var attr = AttributedString(text.string)
        attr.foregroundColor = baseColor
        if let font = styledFont() { attr.font = font }
        if strikethrough { attr.strikethroughStyle = .single }
        return attr
    } else if let emphasis = markup as? Emphasis {
        var result = AttributedString()
        for child in emphasis.children {
            result += attributedFragment(for: child, isDarkMode: isDarkMode, bold: bold, italic: true, strikethrough: strikethrough)
        }
        return result
    } else if let strong = markup as? Strong {
        var result = AttributedString()
        for child in strong.children {
            result += attributedFragment(for: child, isDarkMode: isDarkMode, bold: true, italic: italic, strikethrough: strikethrough)
        }
        return result
    } else if let strikethroughNode = markup as? Strikethrough {
        var result = AttributedString()
        for child in strikethroughNode.children {
            result += attributedFragment(for: child, isDarkMode: isDarkMode, bold: bold, italic: italic, strikethrough: true)
        }
        return result
    } else if let codeSpan = markup as? InlineCode {
        var attr = AttributedString(codeSpan.code)
        attr.foregroundColor = baseColor
        attr.font = .system(.body, design: .monospaced)
        attr.backgroundColor = isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        return attr
    } else if let mdLink = markup as? MarkdownLink {
        var result = AttributedString()
        for child in mdLink.children {
            result += attributedFragment(for: child, isDarkMode: isDarkMode, bold: bold, italic: italic, strikethrough: strikethrough)
        }
        result.foregroundColor = .blue
        result.underlineStyle = .single
        if let destination = mdLink.destination, let url = URL(string: destination) {
            result.link = url
        }
        return result
    } else if markup is SoftBreak {
        return AttributedString(" ")
    } else if markup is LineBreak {
        return AttributedString("\n")
    } else {
        // Fallback for markup types we don't specifically style (rare/exotic nesting).
        let fallbackText = (markup as? InlineMarkup)?.plainText ?? ""
        var attr = AttributedString(fallbackText)
        attr.foregroundColor = baseColor
        return attr
    }
}

struct MarkdownContentView: View {
    let document: Document
    let isDarkMode: Bool

    @State private var selectedDiagramSource: String?
    @State private var selectedDiagramPreview: NSImage?
    @State private var showDiagramViewer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(document.children.enumerated()), id: \.offset) { index, block in
                    MarkdownBlockView(
                        block: block,
                        isDarkMode: isDarkMode,
                        onDiagramSelected: { source, preview in
                            selectedDiagramSource = source
                            selectedDiagramPreview = preview
                            showDiagramViewer = true
                        }
                    )
                    .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: isDarkMode ? .black : .white))
        .onReceive([showDiagramViewer].publisher) { value in
            if value, let source = selectedDiagramSource, let preview = selectedDiagramPreview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    DiagramWindowManager.shared.openDiagramWindow(source: source, previewImage: preview, isDarkMode: isDarkMode)
                    showDiagramViewer = false
                }
            }
        }
    }
}

struct MarkdownBlockView: View {
    let block: Markup
    let isDarkMode: Bool
    let onDiagramSelected: ((String, NSImage) -> Void)?

    var body: some View {
        Group {
            if let heading = block as? Heading {
                HeadingView(heading: heading, isDarkMode: isDarkMode)
            } else if let paragraph = block as? Paragraph {
                ParagraphView(paragraph: paragraph, isDarkMode: isDarkMode)
            } else if let codeBlock = block as? CodeBlock {
                CodeBlockView(codeBlock: codeBlock, isDarkMode: isDarkMode, onDiagramSelected: onDiagramSelected)
            } else if let list = block as? UnorderedList {
                UnorderedListView(list: list, isDarkMode: isDarkMode)
            } else if let list = block as? OrderedList {
                OrderedListView(list: list, isDarkMode: isDarkMode)
            } else if let blockQuote = block as? BlockQuote {
                BlockQuoteView(blockQuote: blockQuote, isDarkMode: isDarkMode, onDiagramSelected: onDiagramSelected)
            } else if let table = block as? MarkdownTable {
                TableView(table: table, isDarkMode: isDarkMode)
            } else if block is ThematicBreak {
                Divider()
                    .padding(.vertical, 8)
            } else {
                Text("Unsupported block type")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Heading
struct HeadingView: View {
    let heading: Heading
    let isDarkMode: Bool

    var body: some View {
        let fontSize: CGFloat = {
            switch heading.level {
            case 1: return 32
            case 2: return 28
            case 3: return 24
            case 4: return 20
            case 5: return 18
            case 6: return 16
            default: return 16
            }
        }()

        Text(buildAttributedString(from: heading, isDarkMode: isDarkMode))
            .font(.system(size: fontSize, weight: .semibold, design: .default))
            .foregroundColor(isDarkMode ? .white : .black)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

// MARK: - Paragraph
struct ParagraphView: View {
    let paragraph: Paragraph
    let isDarkMode: Bool

    var body: some View {
        Text(buildAttributedString(from: paragraph, isDarkMode: isDarkMode))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Code Block
struct CodeBlockView: View {
    let codeBlock: CodeBlock
    let isDarkMode: Bool
    let onDiagramSelected: ((String, NSImage) -> Void)?

    var body: some View {
        let language = codeBlock.language ?? "plain"
        let isMermaid = language.lowercased() == "mermaid"

        if isMermaid {
            MermaidBlockView(code: codeBlock.code, isDarkMode: isDarkMode, onDiagramSelected: onDiagramSelected)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty && language != "plain" {
                    Text(language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text(codeBlock.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isDarkMode ? .white : .black)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: isDarkMode ? .darkGray : NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
            }
            .cornerRadius(6)
            .border(Color.gray.opacity(0.3), width: 1)
        }
    }
}

// MARK: - Mermaid Block
struct MermaidBlockView: View {
    let code: String
    let isDarkMode: Bool
    let onDiagramSelected: ((String, NSImage) -> Void)?

    @State private var svgImage: NSImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Scale for the small inline preview embedded in the document flow.
    private let previewScale = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Rendering diagram...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Diagram Error")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            } else if let image = svgImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .onTapGesture {
                        // Pass the raw source, not this preview image — the full-screen
                        // viewer re-renders from source at a much higher scale so text
                        // stays crisp instead of upscaling this small preview bitmap.
                        onDiagramSelected?(code, image)
                    }
                    .help("Click to open interactive zoom and pan view")
            } else {
                Text("No diagram rendered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: isDarkMode ? NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1) : NSColor(red: 0.98, green: 0.98, blue: 1, alpha: 1)))
        .cornerRadius(8)
        .border(Color.blue.opacity(0.3), width: 1)
        .onAppear {
            renderMermaidDiagram()
        }
        // `.onAppear` only fires once when the view enters the hierarchy — it does NOT
        // refire just because `isDarkMode` changes. Without this, toggling the app theme
        // left already-rendered diagrams in their original color scheme.
        .onChange(of: isDarkMode) { _ in
            renderMermaidDiagram()
        }
    }

    private func renderMermaidDiagram() {
        isLoading = true
        errorMessage = nil

        let capturedCode = code
        let capturedIsDarkMode = isDarkMode
        let scale = previewScale

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let image = try MermaidRenderer.render(code: capturedCode, isDarkMode: capturedIsDarkMode, scale: scale)
                DispatchQueue.main.async {
                    self.svgImage = image
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - mermaid-cli resolution
//
// GUI apps launched from Finder don't inherit the interactive shell's PATH
// (e.g. Homebrew's `eval $(brew shellenv)` in ~/.zshrc), so a plain PATH lookup
// via /usr/bin/env often fails even when mmdc is installed. Check common install
// locations first, falling back to a `which` invocation for anyone launching
// the app from a Terminal-inherited environment.
enum MermaidCLI {
    static let resolvedPath: String? = {
        let candidates = [
            "/opt/homebrew/bin/mmdc",   // Homebrew, Apple Silicon
            "/usr/local/bin/mmdc",      // Homebrew, Intel
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "mmdc"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()

        guard (try? which.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        which.waitUntilExit()

        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }()
}

// MARK: - Shared mermaid-cli invocation
//
// Renders mermaid source to an NSImage via mmdc. `scale` is puppeteer's device-scale
// factor (mmdc's `-s` flag): it renders the same diagram layout at more physical pixels
// per logical point, exactly like a Retina screenshot. Callers pick a scale appropriate
// to how large the result will be displayed — a small inline preview only needs a modest
// scale, while the full-screen viewer re-renders from source at a high scale so text
// stays sharp instead of stretching a low-resolution bitmap.
enum MermaidRenderer {
    struct RenderError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Synchronous — call from a background queue.
    static func render(code: String, isDarkMode: Bool, scale: Int) throws -> NSImage {
        guard let mmdcPath = MermaidCLI.resolvedPath else {
            throw RenderError(message: "mermaid-cli (mmdc) not found.\nInstall with: brew install mermaid-cli")
        }

        let tempDir = NSTemporaryDirectory()
        let id = UUID().uuidString
        let inputFile = (tempDir as NSString).appendingPathComponent("diagram_\(id).mmd")
        let outputFile = (tempDir as NSString).appendingPathComponent("diagram_\(id).png")
        defer {
            try? FileManager.default.removeItem(atPath: inputFile)
            try? FileManager.default.removeItem(atPath: outputFile)
        }

        try code.write(toFile: inputFile, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mmdcPath)
        process.arguments = [
            "-i", inputFile,
            "-o", outputFile,
            "-t", isDarkMode ? "dark" : "default",
            "-s", String(scale),
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()

        // Drain the pipe BEFORE waitUntilExit(). If mermaid-cli/puppeteer writes more
        // than the OS pipe buffer (~64KB) to stderr and nothing is reading it, the child
        // blocks on write() while we block on waitUntilExit() — a classic Process/Pipe
        // deadlock. readDataToEndOfFile() blocks until the write end closes (i.e. the
        // child exits), so this drains safely instead.
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, let image = NSImage(contentsOfFile: outputFile) else {
            let stderrText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RenderError(message: stderrText.isEmpty ? "Diagram render failed" : "Render failed: \(stderrText)")
        }

        return image
    }
}

// MARK: - Lists
struct UnorderedListView: View {
    let list: UnorderedList
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { _, item in
                if let listItem = item as? ListItem {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(isDarkMode ? .white : .black)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(listItem.children.enumerated()), id: \.offset) { _, child in
                                if let paragraph = child as? Paragraph {
                                    ParagraphView(paragraph: paragraph, isDarkMode: isDarkMode)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct OrderedListView: View {
    let list: OrderedList
    let isDarkMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { index, item in
                if let listItem = item as? ListItem {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(isDarkMode ? .white : .black)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(listItem.children.enumerated()), id: \.offset) { _, child in
                                if let paragraph = child as? Paragraph {
                                    ParagraphView(paragraph: paragraph, isDarkMode: isDarkMode)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Block Quote
struct BlockQuoteView: View {
    let blockQuote: BlockQuote
    let isDarkMode: Bool
    let onDiagramSelected: ((String, NSImage) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, isDarkMode: isDarkMode, onDiagramSelected: onDiagramSelected)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: isDarkMode ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1) : NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)))
        .cornerRadius(6)
    }
}

// MARK: - Table
struct TableView: View {
    let table: MarkdownTable
    let isDarkMode: Bool

    var body: some View {
        let headCells = Array(table.head.cells)
        let bodyRows = Array(table.body.rows)
        let alignments = table.columnAlignments

        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headCells.enumerated()), id: \.offset) { index, cell in
                    cellView(cell: cell, isHeader: true, alignment: alignments[safe: index] ?? nil)
                }
            }
            ForEach(Array(bodyRows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { colIndex, cell in
                        cellView(cell: cell, isHeader: false, alignment: alignments[safe: colIndex] ?? nil)
                    }
                }
                .background(rowIndex % 2 == 0 ? Color.clear : Color.gray.opacity(0.06))
            }
        }
        .border(Color.gray.opacity(0.3), width: 1)
        .cornerRadius(6)
    }

    @ViewBuilder
    private func cellView(cell: MarkdownTable.Cell, isHeader: Bool, alignment: MarkdownTable.ColumnAlignment?) -> some View {
        let textAlignment: TextAlignment = {
            switch alignment {
            case .center: return .center
            case .right: return .trailing
            default: return .leading
            }
        }()
        let frameAlignment: Alignment = {
            switch alignment {
            case .center: return .top
            case .right: return .topTrailing
            default: return .topLeading
            }
        }()

        Text(buildAttributedString(from: cell, isDarkMode: isDarkMode))
            .multilineTextAlignment(textAlignment)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .background(isHeader ? Color.gray.opacity(0.18) : Color.clear)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.25), lineWidth: 0.5))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Diagram Viewer Window
struct DiagramViewerWindow: View {
    /// Raw mermaid source — re-rendered fresh at a much higher scale for this window,
    /// rather than stretching the small inline preview bitmap (which is what made text
    /// go blurry when the diagram was expanded).
    let source: String
    /// Shown immediately while the high-resolution version renders in the background.
    let previewImage: NSImage
    let isDarkMode: Bool

    @State private var displayedImage: NSImage
    @State private var isRefining = true

    init(source: String, previewImage: NSImage, isDarkMode: Bool) {
        self.source = source
        self.previewImage = previewImage
        self.isDarkMode = isDarkMode
        _displayedImage = State(initialValue: previewImage)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Diagram Viewer")
                    .font(.headline)

                Spacer()

                if isRefining {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Sharpening…")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Text("\(Int(displayedImage.size.width)) × \(Int(displayedImage.size.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(nsColor: isDarkMode ? .darkGray : .lightGray))
            .border(Color.gray.opacity(0.3), width: 1)

            // Diagram - auto-fitted to screen
            ZStack {
                Color(nsColor: isDarkMode ? .black : .white)

                Image(nsImage: displayedImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .onAppear {
                renderHighResolution()
            }

            // Footer with close instructions
            VStack(spacing: 4) {
                Text("Click the ✕ button in the top-right corner to close this window")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: isDarkMode ? NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1) : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)))
            .border(Color.gray.opacity(0.2), width: 1)
        }
        .background(Color(nsColor: isDarkMode ? .black : .white))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func renderHighResolution() {
        let capturedSource = source
        let capturedIsDarkMode = isDarkMode

        // A high, fixed device-scale factor rather than the small inline preview's scale.
        // Mermaid diagrams are laid out at a fixed logical size regardless of scale, so
        // this simply renders far more physical pixels for the same layout — like a
        // Retina screenshot — which stays crisp even filling a large or 4K/5K screen.
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2
        let scale = max(4, Int((screenScale * 2).rounded(.up)))

        DispatchQueue.global(qos: .userInitiated).async {
            guard let image = try? MermaidRenderer.render(code: capturedSource, isDarkMode: capturedIsDarkMode, scale: scale) else {
                DispatchQueue.main.async {
                    self.isRefining = false
                }
                return
            }
            DispatchQueue.main.async {
                self.displayedImage = image
                self.isRefining = false
            }
        }
    }
}

#Preview {
    MarkdownContentView(document: Document(parsing: "# Hello\n\nThis is a test"), isDarkMode: false)
}
