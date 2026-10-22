#!/usr/bin/env bash
# 拒绝 Package 依赖 Demo、CLI 或 App 运行配置。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if grep -R -n -E 'Demo|lingora-cli|LINGORA_CONTENT_DELIVERY_URL' \
  "$root/Sources" "$root/Package.swift"; then
  echo "SDK target must not reference Demo, CLI, or App environment values" >&2
  exit 1
fi
grep -q 'import Lingora' "$root/Demo/LingoraDemo/ContentView.swift"
swift package --package-path "$root" describe --type json \
  | python3 -c '
import json
import sys

package = json.load(sys.stdin)
targets = {(target["name"], target["type"]) for target in package["targets"]}
expected = {("Lingora", "library"), ("LingoraTests", "test")}
if targets != expected:
    raise SystemExit(f"Package targets must be exactly {sorted(expected)}; got {sorted(targets)}")
'
xcodebuild -project "$root/Demo/LingoraDemo.xcodeproj" -list -json \
  | python3 -c '
import json
import sys

targets = json.load(sys.stdin)["project"]["targets"]
if targets != ["LingoraDemo"]:
    raise SystemExit(f"Demo project must contain only LingoraDemo; got {targets}")
'
grep -q 'XCLocalSwiftPackageReference ".."' "$root/Demo/LingoraDemo.xcodeproj/project.pbxproj"
grep -q 'productName = Lingora' "$root/Demo/LingoraDemo.xcodeproj/project.pbxproj"
