#!/bin/bash

# YouTube Ad Skipper v2 - Build Script

set -e

echo "🔨 Building YouTube Ad Skipper v2..."

# Create build directory
mkdir -p build/YouTubeAdSkipper.app/Contents/MacOS
mkdir -p build/YouTubeAdSkipper.app/Contents/Resources

# Copy Info.plist
cp YouTubeAdSkipper/Info.plist build/YouTubeAdSkipper.app/Contents/

# Compile Swift files
swiftc \
    -o build/YouTubeAdSkipper.app/Contents/MacOS/YouTubeAdSkipper \
    -target arm64-apple-macos12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework Quartz \
    -framework ApplicationServices \
    YouTubeAdSkipper/main.swift \
    YouTubeAdSkipper/AppDelegate.swift

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 App location: build/YouTubeAdSkipper.app"
echo ""
echo "To install:"
echo "  1. Remove old version first (if installed):"
echo "     rm -rf /Applications/YouTubeAdSkipper.app"
echo ""
echo "  2. Move new app to Applications:"
echo "     mv build/YouTubeAdSkipper.app /Applications/"
echo ""
echo "  3. Open the app - it will appear in your menu bar"
echo ""
echo "  4. When Chrome automation permission is requested, click OK"
echo ""
echo "  5. To test: play a YouTube video with ads, click menu bar icon,"
echo "     then 'Test Skip Now' when skip button appears"
echo ""
