import SwiftUI
import Markdown

// Disambiguate types
typealias MarkdownText = Markdown.Text
typealias MarkdownLink = Markdown.Link
typealias MarkdownTable = Markdown.Table

struct MarkdownContentView: View {
    let document: Document
    let isDarkMode: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(document.children.enumerated()), id: \.offset) { index, block in
                    MarkdownBlockView(block: block, isDarkMode: isDarkMode)
                        .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: isDarkMode ? .black : .white))
    }
}

struct MarkdownBlockView: View {
    let block: Markup
    let isDarkMode: Bool

    var body: some View {
        Group {
            if let heading = block as? Heading {
                HeadingView(heading: heading, isDarkMode: isDarkMode)
            } else if let paragraph = block as? Paragraph {
                ParagraphView(paragraph: paragraph, isDarkMode: isDarkMode)
            } else if let codeBlock = block as? CodeBlock {
                CodeBlockView(codeBlock: codeBlock, isDarkMode: isDarkMode)
            } else if let list = block as? UnorderedList {
                UnorderedListView(list: list, isDarkMode: isDarkMode)
            } else if let list = block as? OrderedList {
                OrderedListView(list: list, isDarkMode: isDarkMode)
            } else if let blockQuote = block as? BlockQuote {
                BlockQuoteView(blockQuote: blockQuote, isDarkMode: isDarkMode)
            } else if let table = block as? MarkdownTable {
                TableView(table: table, isDarkMode: isDarkMode)
            } else if let thematicBreak = block as? ThematicBreak {
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
        let text = heading.plainText
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

        Text(text)
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(paragraph.children.enumerated()), id: \.offset) { _, child in
                InlineMarkupView(markup: child, isDarkMode: isDarkMode)
            }
        }
        .lineSpacing(4)
    }
}

// MARK: - Inline Markup
struct InlineMarkupView: View {
    let markup: Markup
    let isDarkMode: Bool

    var body: some View {
        if let text = markup as? MarkdownText {
            SwiftUI.Text(text.string)
                .foregroundColor(isDarkMode ? .white : .black)
        } else if let emphasis = markup as? Emphasis {
            SwiftUI.Text(emphasis.plainText)
                .italic()
                .foregroundColor(isDarkMode ? .white : .black)
        } else if let strong = markup as? Strong {
            SwiftUI.Text(strong.plainText)
                .bold()
                .foregroundColor(isDarkMode ? .white : .black)
        } else if let strikethrough = markup as? Strikethrough {
            SwiftUI.Text(strikethrough.plainText)
                .strikethrough()
                .foregroundColor(isDarkMode ? .white : .black)
        } else if let mdLink = markup as? MarkdownLink {
            SwiftUI.Link(mdLink.plainText, destination: URL(string: mdLink.destination ?? "") ?? URL(fileURLWithPath: "/"))
                .foregroundColor(.blue)
        } else if let codeSpan = markup as? InlineCode {
            SwiftUI.Text(codeSpan.code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: isDarkMode ? .darkGray : .lightGray))
                .cornerRadius(3)
        } else if let softBreak = markup as? SoftBreak {
            SwiftUI.Text(" ")
        } else if let lineBreak = markup as? LineBreak {
            SwiftUI.Text("\n")
        } else {
            SwiftUI.Text("")
        }
    }
}

// MARK: - Code Block
struct CodeBlockView: View {
    let codeBlock: CodeBlock
    let isDarkMode: Bool

    var body: some View {
        let language = codeBlock.language ?? "plain"
        let isMermaid = language.lowercased() == "mermaid"

        if isMermaid {
            MermaidBlockView(code: codeBlock.code, isDarkMode: isDarkMode)
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

    @State private var svgImage: NSImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
    }

    private func renderMermaidDiagram() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let tempDir = NSTemporaryDirectory()
            let inputFile = (tempDir as NSString).appendingPathComponent("diagram_\(UUID().uuidString).mmd")
            let outputFile = (tempDir as NSString).appendingPathComponent("diagram_\(UUID().uuidString).png")

            do {
                try code.write(toFile: inputFile, atomically: true, encoding: .utf8)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mmdc")
                process.arguments = ["-i", inputFile, "-o", outputFile, "-t", isDarkMode ? "dark" : "default"]

                // Capture stderr for better error messages
                let errorPipe = Pipe()
                process.standardError = errorPipe

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    // Wait a moment for file to be written
                    Thread.sleep(forTimeInterval: 0.5)

                    if let image = NSImage(contentsOfFile: outputFile) {
                        DispatchQueue.main.async {
                            self.svgImage = image
                            self.isLoading = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.errorMessage = "Failed to load diagram file"
                            self.isLoading = false
                        }
                    }
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        self.errorMessage = "Render failed: \(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))"
                        self.isLoading = false
                    }
                }

                try? FileManager.default.removeItem(atPath: inputFile)
                try? FileManager.default.removeItem(atPath: outputFile)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, isDarkMode: isDarkMode)
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
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Text("📊 Table")
                .font(.caption)
                .foregroundColor(.secondary)

            SwiftUI.Text("[Table rendering - use web viewer for full table display]")
                .font(.caption)
                .italic()
                .foregroundColor(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: isDarkMode ? .darkGray : NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
                .cornerRadius(4)
        }
    }
}

#Preview {
    MarkdownContentView(document: Document(parsing: "# Hello\n\nThis is a test"), isDarkMode: false)
}
