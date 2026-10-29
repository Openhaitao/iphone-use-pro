#!/bin/bash
# Only generated build directories are removed. Never touch source, App, logs or pairing data.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f Package.swift && -d Sources && -f scripts/build-app.sh ]] || { echo '不是有效项目目录，停止清理。'; exit 1; }
rm -rf .build
native=third_party/mirrordeck-airplay/native/build
[[ ! -L "$native" ]] || { echo '原生构建目录为符号链接，停止清理。'; exit 1; }
if [[ -d "$native" ]]; then
 for entry in "$native"/* "$native"/.[!.]* "$native"/..?*; do
  [[ -e "$entry" || -L "$entry" ]] || continue
  [[ "${entry##*/}" == libMirrorCore.dylib ]] && continue
  rm -rf "$entry"
 done
fi
echo '编译缓存已清除；可运行 App、原生库及源码已保留。'
