#!/usr/bin/env bash
# 拒绝 Package 依赖 Demo、CLI 或 App 运行配置，并固定 Demo 的安全 push 策略。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/Demo/ci/lingora.dev.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    push = json.load(source)["push"]
if push.get("forceMode") != "KEEP" or push.get("removeOtherKeys") is not False:
    raise SystemExit("Demo push must keep existing values and preserve other server keys")
PY
if grep -R -n -E 'Demo|lingora-cli|LINGORA_CONTENT_DELIVERY_URL' \
  "$root/SDK/Sources" "$root/SDK/Package.swift"; then
  echo "SDK target must not reference Demo, CLI, or App environment values" >&2
  exit 1
fi
if find "$root/SDK" -mindepth 1 -maxdepth 1 \
  ! -name Package.swift \
  ! -name Sources \
  ! -name Tests \
  ! -name README.md \
  ! -name THIRD_PARTY_NOTICES.md \
  ! -name .build \
  ! -name .swiftpm \
  -print -quit | grep -q .; then
  echo "SDK directory contains files outside the publishable Swift Package boundary" >&2
  exit 1
fi
grep -q 'import Lingora' "$root/Demo/LingoraDemo/ContentView.swift"
grep -q 'import LingoraCommon' "$root/Demo/LingoraDemo/ContentView.swift"
grep -q 'table: "common"' "$root/Demo/LingoraCommon/CommonNamespaceView.swift"
grep -q 'Bundle(for: CommonBundleToken.self)' "$root/Demo/LingoraCommon/CommonNamespaceView.swift"
swift package --package-path "$root/SDK" describe --type json \
  | python3 -c '
import json
import sys

package = json.load(sys.stdin)
targets = {(target["name"], target["type"]) for target in package["targets"]}
expected = {("Lingora", "library"), ("LingoraTests", "test")}
if targets != expected:
    raise SystemExit(f"Package targets must be exactly {sorted(expected)}; got {sorted(targets)}")
'
python3 "$root/Demo/scripts/configure_sdk.py" --check
xcodebuild -project "$root/Demo/LingoraDemo.xcodeproj" -list -json \
  | python3 -c '
import json
import sys

targets = set(json.load(sys.stdin)["project"]["targets"])
expected = {"LingoraDemo", "LingoraCommon"}
if targets != expected:
    raise SystemExit(f"Demo project targets must be {sorted(expected)}; got {sorted(targets)}")
'
grep -q 'productName = Lingora' "$root/Demo/LingoraDemo.xcodeproj/project.pbxproj"
grep -q 'productType = "com.apple.product-type.framework"' "$root/Demo/LingoraDemo.xcodeproj/project.pbxproj"
