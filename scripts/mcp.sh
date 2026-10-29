#!/bin/bash
# stdio MCP adapter; the separately started App owns Bluetooth and AirPlay.
set -euo pipefail
cd "$(dirname "$0")/.."
binary="$PWD/build/iPhoneUse.app/Contents/MacOS/iphone-use"
[[ -x "$binary" ]] || { echo '请先运行 安装.command 或 ./scripts/setup.sh。' >&2; exit 1; }
exec "$binary" mcp
