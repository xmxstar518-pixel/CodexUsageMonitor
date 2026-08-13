#!/bin/sh
set -eu

bundle_id="com.xmxstar.CodexUsageMonitor"
target=${1:-"/Applications/Codex 用量监控.app"}

case "$target" in
  *.app) ;;
  *) echo "拒绝删除：目标不是 .app" >&2; exit 2 ;;
esac

if [ ! -d "$target" ]; then
  echo "未找到应用：$target"
  exit 0
fi

actual_id=$(/usr/bin/defaults read "$target/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
if [ "$actual_id" != "$bundle_id" ]; then
  echo "拒绝删除：Bundle ID 不匹配" >&2
  exit 3
fi

/bin/rm -rf -- "$target"
/usr/bin/defaults delete "$bundle_id" >/dev/null 2>&1 || true
/bin/rm -rf -- "$HOME/Library/Caches/$bundle_id"
echo "已卸载 Codex 用量监控；未删除项目源码和 Codex 登录信息。"
