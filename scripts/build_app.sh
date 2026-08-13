#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$project_dir/dist/Codex 用量监控.app"

/bin/rm -rf -- "$app_dir"
/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
/bin/cp "$bin_dir/CodexUsageMonitor" "$app_dir/Contents/MacOS/CodexUsageMonitor"
/bin/cp "$project_dir/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
for localization in en.lproj zh-Hans.lproj; do
  /bin/mkdir -p "$app_dir/Contents/Resources/$localization"
  /bin/cp "$project_dir/Packaging/$localization/InfoPlist.strings" "$app_dir/Contents/Resources/$localization/InfoPlist.strings"
done
/bin/chmod 755 "$app_dir/Contents/MacOS/CodexUsageMonitor"
/usr/bin/codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
