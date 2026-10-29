#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f third_party/mirrordeck-airplay/native/build/libMirrorCore.dylib ]]; then
 ./third_party/mirrordeck-airplay/native/build.sh
fi
swift test
if [[ "${IPHONE_USE_KEEP_BUILD_CACHE:-0}" != 1 ]]; then
 ./scripts/clean-build-cache.sh
else
 echo '已按配置保留编译缓存。'
fi
