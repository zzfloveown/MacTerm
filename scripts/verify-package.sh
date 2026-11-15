#!/bin/bash
set -euo pipefail

# 验证磁盘镜像里的应用，而非构建目录里的可执行文件。
mount="$(mktemp -d "$RUNNER_TEMP/macterm-image.XXXXXX")"
log="$RUNNER_TEMP/macterm-launch.log"
pid=""
cleanup() {
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    hdiutil detach "$mount" -quiet || true
    rmdir "$mount" || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount" -quiet dist/MacTerm.dmg
app="$mount/MacTerm.app"
test -d "$app"
test -x "$app/Contents/Helpers/SSHAskPass"
test "$(readlink "$mount/Applications")" = /Applications
codesign --verify --deep --strict "$app"
test "$(lipo -archs "$app/Contents/MacOS/MacTerm")" = arm64
test "$(lipo -archs "$app/Contents/Helpers/SSHAskPass")" = arm64
"$app/Contents/MacOS/MacTerm" >"$log" 2>&1 &
pid=$!
sleep 5
if ! kill -0 "$pid" 2>/dev/null; then
    cat "$log"
    exit 1
fi
