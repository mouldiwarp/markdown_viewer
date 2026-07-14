# Markdown Viewer

A fully native macOS application for viewing Markdown files with Mermaid diagram support.

## Features

- **Native Swift/SwiftUI UI** — Fast and responsive, 100% native code
- **Full GitHub-flavored Markdown** — Headings, lists, code blocks, blockquotes, tables, and more
- **Mermaid Diagram Rendering** — Architecture diagrams, flowcharts, sequence diagrams, etc. rendered as images
- **Dark/Light Theme Toggle** — Seamless theme switching with diagram re-rendering
- **File Handling** — Open via file picker (Cmd+O), drag-and-drop, or double-click .md files
- **Default App** — Registered as the default application for .md files on macOS

## Requirements

- macOS 13.0 or later
- Swift 5.9+
- Homebrew (for mermaid-cli dependency)

## Installation

### From Source

1. Clone the repository
2. Build the app:
   ```bash
   swift build -c release
   ```
3. The executable will be at `.build/release/MarkdownViewerNative`

### As macOS App

1. Create the app bundle:
   ```bash
   mkdir -p "Markdown Viewer.app/Contents/MacOS"
   mkdir -p "Markdown Viewer.app/Contents/Resources"
   cp .build/release/MarkdownViewerNative "Markdown Viewer.app/Contents/MacOS/"
   ```

2. Copy the Info.plist to `Markdown Viewer.app/Contents/`

3. Move to Applications: `mv "Markdown Viewer.app" /Applications/`

## Dependencies

### Runtime

- **mermaid-cli** — For rendering Mermaid diagrams
  ```bash
  brew install mermaid-cli
  npx puppeteer browsers install chrome-headless-shell
  ```

### Build

- **swift-markdown** — Apple's Markdown parsing library

## Usage

1. Double-click the Markdown Viewer app
2. Click "Open File…" or press Cmd+O to open a markdown file
3. Drag-and-drop .md files onto the window
4. Toggle between light/dark theme with the button in the toolbar

## Architecture

- **MarkdownViewerNativeApp.swift** — App entry point and file handling
- **ContentView.swift** — Main UI and file management
- **MarkdownContentView.swift** — Markdown rendering engine with SwiftUI views for each block type

## Rendering

- Markdown parsed using Apple's `swift-markdown` library
- Each markdown block type (heading, paragraph, code block, etc.) rendered with a dedicated SwiftUI view
- Mermaid diagrams extracted from code blocks and rendered to PNG using `mermaid-cli`
- Syntax highlighting for code blocks uses language detection

## License

MIT

## Author

Created with Claude Code
