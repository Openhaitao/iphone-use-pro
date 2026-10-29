#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || { echo '仅支持 Apple Silicon Mac。'; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ]] || { echo '当前交付版要求 macOS 27+。'; exit 1; }
[[ -d build/iPhoneUse.app ]] || { echo '请先运行 安装.command'; exit 1; }
if curl -fsS --max-time 2 http://127.0.0.1:7390/status >/dev/null 2>&1; then
 echo '7390 已有服务运行。请先退出已有 iPhone Use，再启动本副本。'; exit 1
fi
iface="${IPHONE_USE_AIRPLAY_INTERFACE:-$(networksetup -listallhardwareports | awk '/Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2; exit}')}"
[[ -n "$iface" ]] || { echo '无法识别 Wi-Fi 网卡，请设置 IPHONE_USE_AIRPLAY_INTERFACE。'; exit 1; }
ifconfig "$iface" | grep -q 'status: active' || { echo "Wi-Fi 网卡 $iface 未连接，请先连接 Wi-Fi。"; exit 1; }
receiver="${IPHONE_USE_AIRPLAY_NAME:-iPhone Use Pro}"
logdir="$HOME/Library/Logs/iphone-use-pro"
mkdir -p "$logdir"
open -g --env IPHONE_USE_SCREEN=airplay --env "IPHONE_USE_ACTION_GAP_MS=${IPHONE_USE_ACTION_GAP_MS:-120}" --env "IPHONE_USE_AIRPLAY_INTERFACE=$iface" --env "IPHONE_USE_AIRPLAY_NAME=$receiver" --stdout "$logdir/stdout.log" --stderr "$logdir/app.log" "$PWD/build/iPhoneUse.app"
ready=false
for attempt in {1..20}; do
 if curl -fsS --max-time 1 http://127.0.0.1:7390/status >/dev/null 2>&1; then ready=true; break; fi
 sleep 0.25
done
[[ "$ready" == true ]] || { echo "启动未就绪，请查看 $logdir/app.log"; exit 1; }
echo "服务已就绪。允许蓝牙和本地网络；在 iPhone 屏幕镜像选择 ${receiver}。"
echo "日志：${logdir}；连接状态：http://127.0.0.1:7390/status"
