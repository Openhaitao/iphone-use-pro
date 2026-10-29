#!/bin/bash
set -euo pipefail
# Finder/Terminal may not inherit the Homebrew shell environment.
if ! command -v brew >/dev/null && [[ -x /opt/homebrew/bin/brew ]]; then
 export PATH="/opt/homebrew/bin:$PATH"
fi
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo '仅支持 Apple Silicon Mac。'; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ]] || { echo '当前交付版要求 macOS 27+。'; exit 1; }
xcrun --find swift >/dev/null || { echo '先安装 Xcode Command Line Tools：xcode-select --install'; exit 1; }
command -v brew >/dev/null || { echo '请先从 https://brew.sh 安装 Homebrew，再重新运行。'; exit 1; }
missing=()
for formula in cmake pkgconf openssl@3 libplist; do
 brew list --versions "$formula" >/dev/null 2>&1 || missing+=("$formula")
done
if (( ${#missing[@]} )); then brew install "${missing[@]}"; fi
export HOMEBREW_PREFIX="$(brew --prefix)"
export PKG_CONFIG_PATH="$HOMEBREW_PREFIX/opt/openssl@3/lib/pkgconfig:$HOMEBREW_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
./scripts/check-environment.sh
(cd third_party/mirrordeck-airplay && ./native/build.sh)
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}" ./scripts/build-app.sh
echo '安装构建完成。双击 启动.command，按 README 中的首次连接步骤操作。'
