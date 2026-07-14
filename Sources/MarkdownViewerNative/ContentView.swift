import SwiftUI
import Markdown

// MARK: - Window Manager
class DiagramWindowManager: NSObject, NSWindowDelegate {
    static let shared = DiagramWindowManager()
    private var windows: [NSWindow] = []

    func openDiagramWindow(image: NSImage, isDarkMode: Bool) {
        DispatchQueue.main.async { [weak self] in
            let window = NSWindow(
                contentRect: NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.title = "Diagram Viewer"
            window.delegate = self

            let contentView = DiagramViewerWindow(image: image, isDarkMode: isDarkMode)
            let hostingView = NSHostingView(rootView: contentView)
            hostingView.autoresizingMask = [.width, .height]

            window.contentView = hostingView
            window.isReleasedWhenClosed = true

            self?.windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            windows.removeAll { $0 === window }
        }
    }
}

struct ContentView: View {
    @State private var document: Document?
    @State private var filename: String = "No file loaded"
    @State private var isDarkMode = false
    @Environment(\.colorScheme) var systemColorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Text("📄 Markdown Viewer")
                    .font(.headline)

                Spacer()

                Text(filename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button(action: showFileDialog) {
                    Text("Open File…")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(action: toggleTheme) {
                    Text(isDarkMode ? "☀️ Light" : "🌙 Dark")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color(nsColor: .controlBackgroundColor))
            .border(Color(nsColor: .separatorColor), width: 1)

            // Content
            if let document = document {
                MarkdownContentView(document: document, isDarkMode: isDarkMode)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        Text("Open a Markdown File")
                            .font(.headline)

                        Text("Click \"Open File…\" or press Cmd+O")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Drag and drop a .md file onto this window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .onAppear {
            setupTheme()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMarkdownFile"))) { notification in
            if let url = notification.object as? URL {
                loadFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowFileDialog"))) { _ in
            showFileDialog()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadObject(ofClass: NSURL.self) { url, _ in
                    if let url = url as? URL {
                        DispatchQueue.main.async {
                            loadFile(url: url)
                        }
                    }
                }
            }
            return true
        }
    }

    private func setupTheme() {
        isDarkMode = systemColorScheme == .dark
    }

    private func toggleTheme() {
        isDarkMode.toggle()
    }

    private func showFileDialog() {
        let dialog = NSOpenPanel()
        dialog.title = "Open Markdown File"
        dialog.message = "Choose a markdown file to open"
        dialog.allowedFileTypes = ["md", "markdown", "mdown", "markdn", "mdwn", "mkd", "mkdn", "txt"]
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories = false
        dialog.canCreateDirectories = false

        if let window = NSApplication.shared.mainWindow {
            dialog.beginSheetModal(for: window) { response in
                if response == .OK, let url = dialog.url {
                    loadFile(url: url)
                }
            }
        }
    }

    private func loadFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            document = Document(parsing: content, options: .parseBlockDirectives)
            filename = url.lastPathComponent
        } catch {
            filename = "Error loading file"
            print("Error: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
