#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_BIN="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
PLUGIN_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$PROJECT_DIR/dist/AILimiter.app"
ENTITLEMENTS="$PROJECT_DIR/Resources/AILimiter.entitlements"

echo "🚀 [AILimiter] Začínám sestavení zabezpečené macOS Menu Bar aplikace..."

# Vytvoření adresářů
rm -rf "$BUILD_DIR" "$PROJECT_DIR/dist"
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Vyhledání všech Swift souborů
SWIFT_FILES=$(find "$PROJECT_DIR/Sources/AILimiter" -name "*.swift" -type f)

echo "📦 Kompiluji zdrojové soubory Swiftu..."
"$SWIFT_BIN" \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -plugin-path "$PLUGIN_PATH" \
    -O \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework UserNotifications \
    -framework Security \
    $SWIFT_FILES \
    -o "$APP_BUNDLE/Contents/MacOS/AILimiter"

# Kopírování Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Nastavení spustitelnosti
chmod +x "$APP_BUNDLE/Contents/MacOS/AILimiter"

# Podpis aplikace se striktním App Sandboxem (zakazuje čtení jakýchkoliv souborů v systému)
echo "🔒 Aplikuji striktní App Sandbox a bezpečnostní oprávnění..."
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "✅ [AILimiter] Úspěšně sestaveno a zabezpečeno do $APP_BUNDLE"

if [ "$1" == "run" ]; then
    echo "▶️ Spouštím aplikaci do menu baru..."
    open "$APP_BUNDLE"
elif [ "$1" == "install" ]; then
    echo "📥 Instaluji do /Applications/AILimiter.app..."
    rm -rf "/Applications/AILimiter.app"
    cp -R "$APP_BUNDLE" "/Applications/"
    echo "✅ Nainstalováno! Aplikaci najdeš v /Applications."
fi
