#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' "$project_root/pubspec.yaml" | head -n 1)"
bundle="$project_root/build/linux/x64/release/bundle"
appdir="$project_root/build/linux/appimage/AppDir"
output="$project_root/dist/Moment-${version}-x86_64.AppImage"

if [[ ! -x "$bundle/moment" ]]; then
  echo "Missing Linux release bundle. Run: flutter build linux --release" >&2
  exit 1
fi
command -v linuxdeploy >/dev/null || {
  echo "linuxdeploy is required to assemble the AppImage" >&2
  exit 1
}
command -v appimagetool >/dev/null || {
  echo "appimagetool is required to assemble the AppImage" >&2
  exit 1
}

rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
  "$appdir/usr/share/metainfo" "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle/." "$appdir/usr/bin/"
cp "$project_root/linux/packaging/io.github.qwqwqwert.moment.desktop" \
  "$appdir/usr/share/applications/io.github.qwqwqwert.moment.desktop"
cp "$project_root/linux/packaging/io.github.qwqwqwert.moment.appdata.xml" \
  "$appdir/usr/share/metainfo/io.github.qwqwqwert.moment.appdata.xml"
cp "$project_root/windows/runner/resources/moment_icon.png" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/io.github.qwqwqwert.moment.png"

linuxdeploy --appdir "$appdir" \
  --desktop-file "$appdir/usr/share/applications/io.github.qwqwqwert.moment.desktop" \
  --icon-file "$appdir/usr/share/icons/hicolor/512x512/apps/io.github.qwqwqwert.moment.png"
mkdir -p "$(dirname "$output")"
appimagetool "$appdir" "$output"
chmod +x "$output"
echo "Created $output"
