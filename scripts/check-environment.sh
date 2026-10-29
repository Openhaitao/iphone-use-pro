#!/bin/bash
set -euo pipefail
# Finder/Terminal may not inherit the Homebrew shell environment.
if ! command -v brew >/dev/null && [[ -x /opt/homebrew/bin/brew ]]; then
 export PATH="/opt/homebrew/bin:$PATH"
fi
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo '当前交付版仅支持 Apple Silicon Mac。'; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[[ "$major" -ge 27 ]] || { echo '当前交付版要求 macOS 27 或更高；旧版本尚未验证。'; exit 1; }
xcrun --find swift >/dev/null
for tool in cmake pkg-config; do command -v "$tool" >/dev/null || { echo "缺少 $tool，请运行安装脚本。"; exit 1; }; done
pkg-config --exists libplist-2.0 || { echo '缺少 libplist，请运行安装脚本。'; exit 1; }
brew_prefix="$(brew --prefix 2>/dev/null || true)"
PKG_CONFIG_PATH="$brew_prefix/opt/openssl@3/lib/pkgconfig:${PKG_CONFIG_PATH:-}" pkg-config --exists 'openssl >= 1.1.1' || { echo '缺少 OpenSSL，请运行安装脚本。'; exit 1; }
echo '环境检查通过。其他机器的兼容性仍需实际连接测试。'
