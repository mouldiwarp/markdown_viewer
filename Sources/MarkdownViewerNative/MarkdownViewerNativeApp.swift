import SwiftUI
import AppKit

@main
struct MarkdownViewerNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .appVisibility) {
                Button("Open File…") {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowFileDialog"), object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.pathExtension.lowercased() == "md" ||
               url.pathExtension.lowercased() == "markdown" ||
               url.lastPathComponent.hasSuffix(".md") {
                NotificationCenter.default.post(name: NSNotification.Name("OpenMarkdownFile"), object: url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as default app for .md files
        let bundleID = Bundle.main.bundleIdentifier ?? "com.markdown.viewer.native"
        let fileType = "com.markdown.text" as CFString
        let success = LSSetDefaultRoleHandlerForContentType(fileType, .all, bundleID as CFString)
        if success == noErr {
            print("✅ Registered as default for .md files")
        }
    }
}
