# Markdown Viewer — Application Specification

This document specifies the behavior, architecture, and implementation details of
**Markdown Viewer**, a native macOS application, in enough detail to build a
functionally equivalent replica without reading the source.

---

## 1. Purpose

A standalone macOS app that renders `.md` files as formatted documents — headings,
lists, tables, code blocks, and inline formatting — with the one non-standard
feature that fenced code blocks tagged `mermaid` render as actual diagram images
instead of code text, and any diagram can be opened in a dedicated full-screen,
high-resolution viewer.

It is a *viewer*, not an editor: there is no text editing, no saving, no
document model beyond "the currently loaded file."

---

## 2. Platform & Tech Stack

| Layer | Choice |
|---|---|
| OS target | macOS 13.0 (Ventura) or later |
| Language | Swift 5.9 |
| UI framework | SwiftUI, with targeted AppKit interop (`NSWindow`, `NSOpenPanel`, `NSHostingView`) |
| Build system | Swift Package Manager (no Xcode project file) |
| Markdown parsing | [`apple/swift-markdown`](https://github.com/apple/swift-markdown) ≥ 0.4.0 |
| Diagram rendering | External CLI: [`@mermaid-js/mermaid-cli`](https://github.com/mermaid-js/mermaid-cli) (`mmdc`), via Homebrew (`brew install mermaid-cli`) |
| Distribution | Unsigned (ad-hoc `codesign -s -`) `.app` bundle, built and packaged by a shell script — not through the App Store or a Developer ID |

**Why these choices matter for a replica:**
- SwiftUI is used for the whole UI; AppKit is reached into only where SwiftUI has
  no equivalent (native file picker, multiple independent OS-level windows, screen
  DPI query).
- Mermaid rendering is **not** reimplemented in Swift. It shells out to Node-based
  `mmdc`, which itself drives headless Chrome via Puppeteer. This is an external
  process dependency, not a library the app links against — the app must locate
  `mmdc` on disk at runtime (see §5.6).
- There is no persistence layer, no network access, and no sandboxing/entitlements
  configured — the executable runs as a plain ad-hoc-signed binary.

---

## 3. High-Level Architecture

```mermaid
flowchart TB
    subgraph App["MarkdownViewerNativeApp (SwiftUI App)"]
        AD[AppDelegate]
        CV[ContentView — toolbar, file loading, theme state]
    end

    subgraph Render["Markdown Rendering (MarkdownContentView.swift)"]
        MCV[MarkdownContentView]
        MBV[MarkdownBlockView — dispatches by block type]
        AttrStr["buildAttributedString / attributedFragment\n(shared inline-formatting engine)"]
        MER[MermaidBlockView — inline diagram preview]
        TBL[TableView — Grid-based table]
    end

    subgraph Diagram["Diagram Viewer Window (separate NSWindow)"]
        DWM[DiagramWindowManager — singleton, owns window lifetimes]
        DVW[DiagramViewerWindow — full-screen, high-res re-render]
    end

    subgraph External["External process"]
        MMDC["mmdc CLI (mermaid-cli)\nspawns headless Chrome via Puppeteer"]
    end

    AD -- "Finder Open / drag-drop" --> CV
    CV -- "Document (swift-markdown AST)" --> MCV
    MCV --> MBV
    MBV -->|Heading/Paragraph/Table cell text| AttrStr
    MBV -->|"```mermaid block"| MER
    MBV -->|table block| TBL
    MER -- "click: (source, previewImage)" --> DWM
    DWM --> DVW
    MER -- "Process()" --> MMDC
    DVW -- "Process() at higher -s scale" --> MMDC
    MMDC -- "PNG file" --> MER
    MMDC -- "PNG file" --> DVW
```

---

## 4. File / Module Structure

```
MarkdownViewerNative/
├── Package.swift                                  # SPM manifest, macOS 13 target, swift-markdown dependency
├── build.sh                                        # build → .app bundle → ad-hoc codesign → lsregister
├── dist/                                            # build.sh output (gitignored)
└── Sources/MarkdownViewerNative/
    ├── MarkdownViewerNativeApp.swift                # @main entry point, AppDelegate, menu commands
    ├── ContentView.swift                            # Main window: toolbar, file loading, DiagramWindowManager
    └── MarkdownContentView.swift                    # Everything else: markdown → SwiftUI rendering,
                                                       # mermaid rendering, diagram viewer window
```

There is no Xcode project; `swift build` / `swift run` work directly. The app
bundle (`Info.plist`, code signature, Launch Services registration) is assembled
entirely by `build.sh`, not by Xcode's build system — see §7.

---

## 5. Functional Specification

### 5.1 Application Shell & Window

- One `WindowGroup` scene containing `ContentView`, minimum size 800×600.
- Toolbar (top bar) contains, left to right: app title/icon, spacer, current
  filename (or "No file loaded"), "Open File…" button, theme toggle button
  (🌙 Dark / ☀️ Light).
- Below the toolbar: either the rendered document (scrollable), or an empty-state
  placeholder ("Open a Markdown File", with hints for the button, Cmd+O, and
  drag-and-drop) when nothing is loaded.
- Theme defaults to the system's current appearance at launch
  (`\.colorScheme` read once in `.onAppear`), then is fully manual — toggling it
  does **not** track subsequent system appearance changes.
- A single app-level menu command, "Open File…" under Cmd+O, posts an
  `NSNotification` (`"ShowFileDialog"`) that `ContentView` listens for. This is
  the *only* place Cmd+O is declared — it is intentionally not duplicated as a
  `.keyboardShortcut` on the toolbar button, to avoid two competing declarations
  of the same shortcut.

### 5.2 File Loading

Three entry points, all converging on one `loadFile(url:)` function:

1. **Open File button / Cmd+O** → `NSOpenPanel`, filtered to content types
   resolved from extensions `md, markdown, mdown, markdn, mdwn, mkd, mkdn, txt`
   (via `UTType(filenameExtension:)`, not the deprecated `allowedFileTypes`).
   - The panel is presented as a sheet on "the real app window" — found by
     filtering `NSApplication.shared.windows` to visible windows that are **not**
     diagram-viewer windows (`DiagramWindowManager.isDiagramWindow`), since those
     are also plain `NSWindow`s and can otherwise become `NSApp.mainWindow`.
   - If no such window is found, falls back to a standalone `runModal()` dialog
     rather than silently doing nothing.
2. **Drag-and-drop** — `.onDrop(of: [.fileURL])` on the whole `ContentView`;
   takes the first dropped item's URL.
3. **Finder / "Open With" / double-click a `.md` file** — `AppDelegate.application(_:open:)`
   filters dropped URLs to `.md`/`.markdown` extensions and posts an
   `"OpenMarkdownFile"` notification carrying the URL, which `ContentView`
   observes.

`loadFile(url:)` behavior:
```
read file as UTF-8 string
    → Document(parsing: content, options: .parseBlockDirectives)   // swift-markdown
    → store in @State var document
    → update filename label to url.lastPathComponent
on failure: filename label becomes "Error loading file", error printed to console
    (no user-facing error dialog)
```

Loading a new file **replaces** the whole document tree; there is no
merge/append, and any diagrams from a previously loaded file are simply
discarded along with their SwiftUI view identities (this also implicitly resets
mermaid-render state per diagram, since `MermaidBlockView` instances are
recreated).

### 5.3 Markdown Rendering Pipeline

`Document(parsing:options:)` (swift-markdown) parses the raw text into an AST.
Top-level children are iterated in `MarkdownContentView`, wrapped in a
`ScrollView` + `VStack`, max content width 900pt, centered, 40pt horizontal /
20pt vertical padding, 16pt spacing between blocks.

`MarkdownBlockView` is the block-type dispatcher — it downcasts the generic
`Markup` node to a concrete type and routes to the matching renderer:

| swift-markdown type | Renderer | Notes |
|---|---|---|
| `Heading` | `HeadingView` | Font size by level: h1=32, h2=28, h3=24, h4=20, h5=18, h6=16pt, `.semibold` |
| `Paragraph` | `ParagraphView` | See §5.4 |
| `CodeBlock` | `CodeBlockView` | Branches to `MermaidBlockView` if `language == "mermaid"` (case-insensitive), else plain monospaced block |
| `UnorderedList` | `UnorderedListView` | Bullet "•" + paragraph per `ListItem`; **only renders `Paragraph` children of a list item** — nested lists, code blocks, or block quotes inside a list item are silently dropped |
| `OrderedList` | `OrderedListView` | Same limitation as above, with "N." numbering (SwiftUI-side index, not swift-markdown's own start-number) |
| `BlockQuote` | `BlockQuoteView` | 4pt blue left bar, tinted background, recurses through `MarkdownBlockView` for full nested-block support (not paragraph-only) |
| `Table` | `TableView` | See §5.5 |
| `ThematicBreak` | `Divider()` | — |
| anything else | fallback `Text("Unsupported block type")`, gray caption | |

### 5.4 Inline Formatting Engine

All inline content (inside paragraphs, headings, and table cells) is rendered
through **one shared code path**, not per-child SwiftUI views:

```
buildAttributedString(from: container, isDarkMode:) -> AttributedString
    walks container.children, concatenating attributedFragment(...) for each
```

`attributedFragment(for:isDarkMode:bold:italic:strikethrough:)` recursively
builds a single `AttributedString`, threading `bold`/`italic`/`strikethrough`
flags down through nested `Strong`/`Emphasis`/`Strikethrough` so that e.g.
`**bold _italic_**` compounds correctly instead of the inner formatting being
discarded. Per swift-markdown type:

- `Text` → plain run, foreground color set, `.bold()`/`.italic()` applied to the
  `Font` if flagged, `.strikethroughStyle` if flagged.
- `Emphasis` → recurse into children with `italic = true`.
- `Strong` → recurse into children with `bold = true`.
- `Strikethrough` → recurse into children with `strikethrough = true`.
- `InlineCode` → monospaced font, subtle background highlight
  (`white 15% opacity` in dark mode / `black 8% opacity` in light mode) — this
  is a flat highlight, not a padded/rounded pill, since `AttributedString`
  doesn't support per-range corner radius or padding.
- `Link` → recurses into children for the link's display text (preserving any
  nested bold/italic inside the link label), sets `.foregroundColor = .blue`,
  `.underlineStyle = .single`, and `.link = URL(string: destination)`. This
  renders as a real inline, clickable, **line-wrapping** hyperlink embedded in
  the flowing text (via `Text(AttributedString)`'s native link support,
  available macOS 12+) — not a separate `Link` view breaking the paragraph.
- `SoftBreak` → single space. `LineBreak` → `"\n"`.
- Anything else (rare/exotic nesting) → falls back to `.plainText` if the node
  conforms to `InlineMarkup`, else empty string.

The resulting single `AttributedString` is rendered with one `Text(...)` view
per paragraph/heading/cell — critically, **not** one SwiftUI view per inline
child. This is what makes a paragraph wrap and flow as a normal paragraph
rather than each formatted run (a bold word, a link, ...) breaking onto its own
line.

`ParagraphView` additionally applies `.lineSpacing(4)` and
`.fixedSize(horizontal: false, vertical: true)` (so it wraps within the
available width rather than clipping/truncating).

### 5.5 Table Rendering

`TableView` uses SwiftUI's `Grid`/`GridRow` (macOS 13+) driven directly by
swift-markdown's real table API — not a placeholder:

- `table.head.cells` → header `GridRow`.
- `table.body.rows` → one `GridRow` per row, `row.cells` per cell.
- `table.columnAlignments: [Table.ColumnAlignment?]` (`.left`/`.center`/`.right`)
  maps to `TextAlignment`/`Alignment` per column, applied per cell (default:
  left).
- Each cell's inline content goes through the same
  `buildAttributedString(from: cell, ...)` engine as paragraphs — full nested
  formatting support inside table cells.
- Header row: semibold weight, `gray 18% opacity` background. Body rows:
  zebra-striped (`gray 6% opacity` on odd row indices, 0-indexed so the first
  data row is plain). Every cell has a hairline `gray 25% opacity` border via
  `.overlay(Rectangle().stroke(...))`. Whole table has a 1pt outer border and
  6pt corner radius.
- No column-span/row-span handling — `Table.Cell.colspan`/`.rowspan` are not
  read; spanning cells render as ordinary single cells.

### 5.6 Mermaid Diagram Rendering

**Detection**: a `CodeBlock` whose `language` (lowercased, trimmed) is exactly
`"mermaid"` renders as `MermaidBlockView` instead of a code block.

**Rendering mechanism** — there is no in-process mermaid renderer. Rendering is
delegated entirely to the external `mmdc` CLI:

```
MermaidRenderer.render(code: String, isDarkMode: Bool, scale: Int) throws -> NSImage
    1. Resolve mmdc's path (see below); throw a user-facing error if not found.
    2. Write `code` to a temp file: $TMPDIR/diagram_<uuid>.mmd
    3. Spawn: mmdc -i <input>.mmd -o <output>.png -t (dark|default) -s <scale>
    4. Capture stderr via a Pipe, and CRITICALLY drain it with
       readDataToEndOfFile() BEFORE calling waitUntilExit() — reading only
       after waitUntilExit() can deadlock if mmdc/Puppeteer writes more than
       the OS pipe buffer (~64KB) to stderr, since the child blocks on a full
       buffer while the parent blocks waiting for it to exit.
    5. On non-zero exit or missing output file: throw with the captured
       stderr text (or a generic message if stderr was empty).
    6. On success: NSImage(contentsOfFile: outputFile), then delete both temp
       files (input and output) via a `defer` block.
```

`-t` (theme) is `"dark"` or `"default"` (mermaid's own theme names — not
`"light"`, which is invalid and errors). `-s` (`--scale`) is Puppeteer's
device-scale factor: it renders the *same diagram layout* at more physical
pixels per logical point (like a Retina screenshot), rather than changing the
diagram's logical size/layout.

**mmdc path resolution** (`MermaidCLI.resolvedPath`, computed once and cached):
GUI apps launched from Finder do not inherit the interactive shell's `PATH`
(e.g. Homebrew's `eval $(brew shellenv)` in `~/.zshrc`), so a naive
`/usr/bin/env mmdc` lookup often fails even when `mmdc` is installed. Resolution
order:
1. `/opt/homebrew/bin/mmdc` (Homebrew, Apple Silicon)
2. `/usr/local/bin/mmdc` (Homebrew, Intel)
3. Fallback: spawn `/usr/bin/env which mmdc` and use its stdout if it points at
   an executable file.
4. If none resolve, `resolvedPath` is `nil` and every render attempt fails with
   an explicit "mermaid-cli (mmdc) not found. Install with: brew install
   mermaid-cli" error (shown inline where the diagram would be).

**Inline preview** (`MermaidBlockView`):
- Renders at a fixed `previewScale = 2` (a light Retina-equivalent — kept
  modest since a document can contain many diagrams and each is an independent
  process spawn).
- States: loading (spinner + "Rendering diagram..."), error (red box with
  message), or the rendered image (`.resizable().scaledToFit()`, max height
  400pt).
- Rendering is kicked off in `.onAppear` (background `DispatchQueue.global`,
  result applied on `DispatchQueue.main`).
- **Theme-change re-render**: `.onAppear` only fires once per view lifetime and
  does *not* refire just because `isDarkMode` changes (SwiftUI doesn't recreate
  the view for a prop change). Since `mmdc -t` bakes the theme into the PNG
  pixels, an explicit `.onChange(of: isDarkMode)` re-invokes the same render
  function whenever the app theme is toggled, so already-rendered diagrams
  update instead of staying stuck in their original color scheme.
- Tapping the rendered image calls `onDiagramSelected?(code, image)` — passing
  the **raw mermaid source string**, not just the bitmap (see §5.7).

### 5.7 Full-Screen Diagram Viewer

Clicking a rendered diagram opens it in a dedicated, separate, resizable
`NSWindow` — not a SwiftUI `.sheet`, and not a same-window overlay — sized to
`NSScreen.main?.visibleFrame` (i.e. opens already filling the screen's usable
area, but remains a normal resizable/closable titled window, not literally
`NSWindow.toggleFullScreen`).

**Why a plain `NSWindow` instead of a SwiftUI `Window`/`.sheet` scene:** to get
independent, simultaneously-resizable windows outside the single `WindowGroup`,
constructed on demand from a click handler rather than declared as a fixed
scene.

**Window lifetime management** (`DiagramWindowManager`, a singleton):
- Holds a strong `[NSWindow]` array — this is the app's own reference-counting
  mechanism for windows it creates outside SwiftUI's scene system.
- **`window.isReleasedWhenClosed` is explicitly set to `false`.** This is
  load-bearing: if `true` (the AppKit default) while the app *also* holds its
  own strong reference, AppKit's release-on-close races against the standard
  close-button's genie/transform-animation teardown, causing a
  `_NSWindowTransformAnimation dealloc` double-release crash
  (`EXC_BAD_ACCESS`/`SIGSEGV`). Since the manager already owns the window's
  lifetime via the array, AppKit must not *also* try to free it.
- `DiagramWindowManager` is the window's `NSWindowDelegate`; on
  `windowWillClose`, the closed window is removed from the array (its only
  remaining strong reference), which is what actually deallocates it — safely,
  after the close animation has been allowed to run to completion.
- `isDiagramWindow(_:)` lets other code (the Open File dialog) distinguish
  these windows from the main app window (see §5.2).

**Content** (`DiagramViewerWindow`):
- Toolbar: "Diagram Viewer" title, a "Sharpening…" spinner+label shown only
  while a background re-render is in flight, and the currently-displayed
  image's pixel dimensions (`W × H`).
- Body: the image, `.resizable().scaledToFit()`, centered with padding, over a
  solid black/white background depending on theme.
- Footer: static hint text, "Click the ✕ button in the top-right corner to
  close this window" (there is deliberately no in-window custom close button,
  no Esc-to-close, and no pan/zoom gesture support — closing is via the
  window's standard titlebar close button only, and viewing is "does the whole
  diagram fit the screen," not manual pan/zoom).
- **Two-phase rendering, not just displaying the inline preview scaled up:**
  1. Constructed with the small `previewImage` already rendered inline
     (§5.6) — shown immediately so the window never opens blank.
  2. On `.onAppear`, kicks off `renderHighResolution()`: re-invokes
     `MermaidRenderer.render` from the **raw mermaid source** (not the bitmap)
     at `scale = max(4, ceil(NSScreen.main.backingScaleFactor * 2))` — i.e. at
     least 4×, and higher still on already-HiDPI screens. This is a fresh
     render of the same diagram layout at far more physical pixels, avoiding
     the blurriness that stretching the small inline-preview bitmap would
     cause.
  3. Once the high-res image is ready, it replaces `displayedImage` (view
     updates, dimension label updates, "Sharpening…" indicator disappears). If
     the high-res render fails for any reason, the low-res preview silently
     remains displayed and the spinner just stops — no error is surfaced here
     (the diagram already rendered successfully once, at preview scale).
- The window does **not** re-render again on manual resize; the high-res pass
  happens exactly once, at open time, sized for the screen it opened on.

### 5.8 Theme System

- A single `@State private var isDarkMode: Bool` on `ContentView`, seeded from
  `\.colorScheme` at first appearance, thereafter fully independent of system
  appearance — it's a manual toggle, not "follow system."
- `isDarkMode` is threaded as a plain `Bool` parameter through every view in
  the render tree (no `@Environment` custom key, no color-scheme override at
  the window level) — every renderer branches its own colors on this
  parameter directly (e.g. `isDarkMode ? .white : .black`).
- Toggling affects: all text colors, code-block backgrounds, table
  header/stripe colors, blockquote background, and (per §5.6) triggers
  re-rendering of every currently-visible mermaid diagram so their baked-in
  theme matches.

### 5.9 macOS Integration

- `Info.plist` declares `CFBundleDocumentTypes` for `md`/`markdown` extensions
  with `CFBundleTypeRole = Editor`, so Finder offers this app in "Open With"
  and (once selected) as a default handler.
- `AppDelegate.applicationDidFinishLaunching` additionally calls
  `LSSetDefaultRoleHandlerForContentType` for the custom UTI
  `"com.markdown.text"` on every launch, attempting to register itself as the
  default handler programmatically (best-effort; failure is only logged, not
  surfaced to the user).
- Bundle identifier: `com.markdown.viewer.native`.

---

## 6. External Dependencies

| Dependency | Role | How the app finds/uses it |
|---|---|---|
| `apple/swift-markdown` (≥0.4.0) | Markdown → AST parsing, linked via SPM | Compile-time Swift Package dependency |
| `mmdc` (`@mermaid-js/mermaid-cli`) | Renders mermaid diagram source → PNG | Runtime subprocess; **not linked**, must be separately installed (`brew install mermaid-cli`) and discoverable via the path resolution in §5.6 |
| Puppeteer / headless Chrome | mmdc's actual rendering engine | Transitive runtime dependency of `mmdc`; if missing, `mmdc` itself fails (surfaces as a render error with mmdc's stderr) |

A replica must reproduce the **subprocess** relationship with mermaid-cli
exactly (spawn `mmdc` with `-i/-o/-t/-s` flags, read stdout/stderr correctly,
handle it being absent) — mermaid is not meant to be reimplemented natively.

---

## 7. Build, Package & Distribution

No Xcode project — pure SPM:

```bash
swift build -c release          # produces .build/release/MarkdownViewerNative
```

`build.sh` (repo root) performs the full packaging sequence, reproducibly:

1. `swift build -c release`
2. Assemble `dist/Markdown Viewer.app/Contents/{MacOS,Resources}`, copy the
   binary in, `chmod +x`.
3. Write `Info.plist` inline (bundle id `com.markdown.viewer.native`, min
   system version 13.0, document-type declarations for `md`/`markdown`).
4. Ad-hoc code sign: `codesign -s - -f <binary>` (no Developer ID — this is
   what makes the app launchable locally without a paid Apple Developer
   account; it is *not* suitable for distribution outside the building
   machine without a real signing identity).
5. Register with Launch Services:
   `.../LaunchServices.framework/Support/lsregister -f <app>`, so Finder/`Open
   With` picks it up immediately without a reboot or manual re-registration.
6. Optional flags: `--install` (copy to `~/Applications`), `--desktop` (copy to
   `~/Desktop`).

`dist/` is gitignored — the packaged `.app` is a build artifact, not checked
in.

---

## 8. Error Handling & Edge Cases (as implemented, not aspirational)

- **File read failure** (bad encoding, permissions, deleted mid-read): caught,
  filename label shows "Error loading file," error is `print()`-ed to console
  only — no alert dialog.
- **mermaid-cli missing entirely**: every diagram in the document shows an
  inline red error box: "mermaid-cli (mmdc) not found. Install with: brew
  install mermaid-cli." The rest of the document still renders normally.
- **Individual diagram syntax error**: that diagram's `MermaidBlockView` shows
  its own red error box with mmdc's stderr text; other diagrams and the rest
  of the document are unaffected (each diagram is rendered independently, not
  as a single all-or-nothing batch).
- **High-res re-render fails in the diagram viewer window**: silently keeps
  showing the already-successful low-res preview; no error box in this
  specific path (only the initial inline render surfaces errors).
- **Open File dialog with no eligible "main" window** (e.g. only diagram
  viewer windows are open, or none): falls back to a standalone `runModal()`
  dialog rather than doing nothing.
- **Dropping a non-markdown file**: not specifically validated — `loadFile`
  attempts to read *any* dropped/opened file as UTF-8 text and parse it as
  markdown; a binary file would likely fail the UTF-8 decode and hit the
  generic file-read-failure path above.
- **Reopening a file while diagrams are still rendering**: safe — each
  `MermaidBlockView` is a fresh SwiftUI view instance tied to the new document
  tree; the old views (and their in-flight background renders, if any)
  are simply discarded/orphaned, not explicitly cancelled.

---

## 9. Known Limitations (intentionally out of scope, not bugs)

- No editing — view-only.
- No syntax highlighting for non-mermaid code blocks (single monospaced color).
- No pan/zoom inside the diagram viewer — it only auto-fits to screen.
- List items only render `Paragraph` content; nested lists/code/quotes inside
  a list item are dropped.
- No table cell colspan/rowspan support.
- Not code-signed with a real Developer ID — Gatekeeper will warn on first
  launch on a machine other than the one that built it, unless the user
  right-click → Open's past it.
- Theme does not follow system appearance changes after launch, only the
  initial value.
- No recent-files list, no window-per-document (loading a new file replaces
  the content of the single main window).

---

## 10. Replica Verification Checklist

A replica should be checked against each of these observable behaviors:

- [ ] Opens to an empty state with correct hint text when launched with no file.
- [ ] Cmd+O, the toolbar button, drag-and-drop, and Finder "Open With" all load a file through the same code path.
- [ ] `# Heading **bold**` renders bold text inside the heading (nested formatting preserved).
- [ ] A paragraph mixing plain text, `**bold**`, `_italic_`, and a `[link](url)` renders as **one flowing, wrapping paragraph** — not one line per formatted span.
- [ ] A link inside bold text (`**[text](url)**`) is both bold and clickable.
- [ ] A GFM table renders as an actual grid with header styling, zebra striping, and correct column alignment (`:--`, `:-:`, `--:`).
- [ ] A ` ```mermaid ` block renders as an image, not code text.
- [ ] Toggling the theme button re-colors the app chrome **and** re-renders every visible diagram in the new mermaid theme.
- [ ] Clicking a diagram opens a separate, screen-filling window immediately showing the diagram, which visibly sharpens a moment later.
- [ ] Closing a diagram window via its titlebar ✕ never crashes, repeatedly, including opening/closing many in a row.
- [ ] With mermaid-cli not installed/found, diagrams show an actionable inline error instead of crashing or hanging.
- [ ] Opening the file dialog while a diagram viewer window is focused still targets the correct (main) window.
