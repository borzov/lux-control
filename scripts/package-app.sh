#!/usr/bin/env bash
set -euo pipefail

version="${1:-0.1.2}"
build_number="${2:-1}"
configuration="${CONFIGURATION:-release}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
app_dir="$dist_dir/LuxControl.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
executable="$repo_root/.build/$configuration/LuxControlApp"
icon_file="$repo_root/Sources/LuxControlApp/Resources/AppIcon.icns"

cd "$repo_root"

swift build -c "$configuration" --product LuxControlApp

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

cp "$executable" "$macos_dir/LuxControl"
chmod 755 "$macos_dir/LuxControl"
cp "$icon_file" "$resources_dir/AppIcon.icns"

cat > "$contents_dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LuxControl</string>
    <key>CFBundleIdentifier</key>
    <string>ru.borzov.lux-control</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>LuxControl</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$contents_dir/Info.plist"

archive="$dist_dir/LuxControl-$version.zip"
rm -f "$archive" "$archive.sha256"
ditto -c -k --keepParent "$app_dir" "$archive"
shasum -a 256 "$archive" > "$archive.sha256"

echo "$archive"
