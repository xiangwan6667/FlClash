#!/bin/sh
set -eu

[ "${PACKAGE_FORMAT:-}" = dmg ] || exit 0

version=$(awk '/^version:/ { split($2, parts, "+"); print parts[1]; exit }' pubspec.yaml)
case "$(uname -m)" in
  arm64) arch=arm64 ;;
  x86_64) arch=amd64 ;;
  *) echo 'Unsupported macOS architecture' >&2; exit 1 ;;
esac

image="$OUTPUT_DIRECTORY/FlClash-Miu-$version-macos-$arch.dmg"
app="$BUILD_OUTPUT_DIRECTORY/FlClash.app"
[ -f "$image" ] && [ -d "$app" ] || {
  echo 'macOS build output was not found' >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/flclash-miu-dmg.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/content/FlClash-Miu"
ditto "$app" "$work/content/FlClash-Miu/FlClash.app"
ln -s /Applications "$work/content/Applications"
printf '%s\n' \
  'Copy the FlClash-Miu folder into Applications, then open FlClash.' \
  '将 FlClash-Miu 文件夹拖入 Applications，然后打开其中的 FlClash。' \
  > "$work/content/README.txt"
hdiutil create -quiet -volname FlClash -srcfolder "$work/content" \
  -format UDZO "$work/isolated.dmg"
mv -f "$work/isolated.dmg" "$image"
