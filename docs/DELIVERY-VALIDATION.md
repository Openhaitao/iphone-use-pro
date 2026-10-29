# 交付验证 2026-10-16

范围：Apple Silicon / macOS 27 开发预览交付。第二台机器测试由用户明确暂缓，不宣称已完成。

已完成：
- Shell 安装、启动及环境检查脚本语法检查通过；当前环境检查通过。
- 从桌面项目内附带源码，通过 CMake --fresh 重建原生库，再重新编译与签名 App 成功；没有依赖旧目录的 CMake 缓存。
- 统一 Swift 与 App 最低系统版本为 27.0，避免之前 macOS 14 声明与原生库 macOS 27 的冲突。
- otool 检查原生库只依赖系统 libSystem，App 内打包该库；不要求接收方已有原机器 Homebrew 动态库路径。
- 已有 7390 服务时，启动脚本明确拒绝启动副本，不停止现有程序。
- 本机原实现已完成拔 USB 后 AirPlay + BLE 计算器输入验收，以及 Eject 弹出屏幕键盘验收。

尚未完成：
- 在其他 Mac 安装、配对和无线控制验收。
- 新交付启动脚本完整重新连接实测（现有用户会话保持运行，没有为测试中断）。
- 正式签名、公证、Intel/旧版 macOS/Windows 支持及长时间重连验收。

安装脚本会通过 Homebrew 安装依赖，需要联网；未在本次验证中重复执行 brew install，原生与 Swift 构建步骤已单独执行。

## GitHub源码发布检查 — 2026-10-29

- 从Git暂存内容导出不带构建产物的独立副本，目录名包含空格。
- 完整 `scripts/setup.sh` 原生库、Swift release App构建和临时签名通过；修复了原生链接导出列表路径含空格时的失败。
- `scripts/test.sh` 的11项回归测试全部通过，成功后自动清理缓存，App与原生库仍保留。
- `codesign --verify --deep --strict` 通过；原生动态库仅依赖系统libSystem，没有原机器Homebrew动态库绝对路径依赖。
- 新的 `scripts/mcp.sh` 通过stdio初始化与8项工具列表验证，标准输出仅为JSON-RPC。
- 补齐原始iPhone Use的MIT声明，保留MirrorDeck与UxPlay许可、源码和修改说明。发布内容不含App、编译缓存、日志、配对数据或手机截图；已扫描凭据模式与本机私有路径。
- 本次没有重启用户现有控制服务，也没有新增第二台Mac的实际配对或手机控制验收。此项限制仍适用。
