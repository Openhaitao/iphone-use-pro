#!/bin/bash
cd "$(dirname "$0")"
./scripts/setup.sh
result=$?
echo "退出代码：$result。按回车关闭。"
read -r
exit "$result"
