#!/bin/bash
#
# Builds MarkdownViewerNative in release mode, packages it as a macOS .app bundle,
# ad-hoc code-signs it, and registers it with Launch Services.
#
# Usage:
#   ./build.sh                 # builds into ./dist/Markdown Viewer.app
#   ./build.sh --install       # also copies the app to ~/Applications
#   ./build.sh --desktop       # also copies the app to ~/Desktop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Markdown Viewer"
BUNDLE_ID="com.markdown.viewer.native"
EXECUTABLE_NAME="MarkdownViewerNative"
DIST_DIR="$SCRIPT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"

echo "==> Building release binary"
swift build -c release

echo "==> Creating app bundle at $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp ".build/release/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/"
chmod +x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> Ad-hoc code signing"
codesign -s - -f "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
codesign -v "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"

echo "==> Registering with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"

for arg in "$@"; do
    case "$arg" in
        --install)
            mkdir -p "$HOME/Applications"
            echo "==> Installing to ~/Applications"
            rm -rf "$HOME/Applications/$APP_NAME.app"
            cp -r "$APP_PATH" "$HOME/Applications/"
            ;;
        --desktop)
            echo "==> Copying to ~/Desktop"
            rm -rf "$HOME/Desktop/$APP_NAME.app"
            cp -r "$APP_PATH" "$HOME/Desktop/"
            ;;
    esac
done

echo "==> Done: $APP_PATH"
