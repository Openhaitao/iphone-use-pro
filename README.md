# iphone-use-pro

本地 Mac 通过 AirPlay 接收 iPhone 画面，通过 BLE HID 发送鼠标与键盘输入。无须 WDA 或 USB，但手机必须在 Mac 蓝牙范围内，并与 Mac 连接同一个局域网。HTTP 控制接口仅监听 `127.0.0.1:7390`。

## 当前支持范围

| 项目 | 状态 |
| --- | --- |
| Apple Silicon、macOS 27.0.1 | 本机编译、无线画面和蓝牙控制已实测 |
| macOS 27+ 其他 Mac | 安装流程已准备，尚待第二台机器实测 |
| macOS 26 及以下、Intel Mac、Windows | 当前交付版不支持，未验证 |
| iPhone 16 Pro | 本机连接实测；其他型号未验证 |

这是开发预览版，使用临时签名，尚未正式签名和公证。不要把本机验证当成其他机器验证。

## 获取项目

公开源码：[Openhaitao/iphone-use-pro](https://github.com/Openhaitao/iphone-use-pro)。需要 **Apple Silicon Mac、macOS 27+、iPhone，以及同一局域网和蓝牙连接**。不是 Windows 安装包，也不会在 iPhone 安装 App。

在 GitHub 页面选择 **Code → Download ZIP** 并解压，或使用：

```sh
git clone https://github.com/Openhaitao/iphone-use-pro.git
cd iphone-use-pro
./scripts/setup.sh
./scripts/start.sh
```

仓库包含所有 AirPlay 原生源码，无需递归下载子模块。安装依赖时需要联网；构建完成后的手机控制在本地进行。

## 安装与启动

1. 解压到可写目录，例如桌面。安装 Apple Xcode Command Line Tools（`xcode-select --install`）以及 [Homebrew](https://brew.sh)。
2. 双击「安装.command」。脚本安装 CMake、pkgconf、OpenSSL、libplist，并从附带源码重新编译原生库和 App。首次需要联网下载编译依赖。无需运行第三方 bootstrap，也不会下载 WDA。
3. 双击「启动.command」。如果提示 7390 已有服务，请先退出旧版 iPhone Use；脚本不会擅自停止其他程序。
4. 允许 Mac 的蓝牙与本地网络权限。临时签名的 App 在重新构建后可能再次请求权限。系统拦截时，核实代码来源后按系统「隐私与安全性」提示处理。

命令行等价入口：`./scripts/setup.sh`、`./scripts/start.sh`。启动时自动识别 Wi-Fi 接口；可用 `IPHONE_USE_AIRPLAY_INTERFACE` 和 `IPHONE_USE_AIRPLAY_NAME` 覆盖。程序没有窗口，使用活动监视器退出 iphone-use。日志在 `~/Library/Logs/iphone-use-pro/`。

## iPhone 首次连接

1. 开启 Wi-Fi 和蓝牙，保持解锁。在「设置 → 辅助功能 → 触控 → 辅助触控」打开辅助触控与「显示屏幕键盘」。
2. 在「设置 → 蓝牙」尝试连接「iPhone Use」，允许配对。本机最初曾需用 Nordic nRF Connect 扫描并连接它，才建立 HID 订阅；这不是已解决的通用配对流程。无法连接时保留日志，不要重置全部网络或删除系统密钥。
3. 打开控制中心 → 屏幕镜像 → 选择「iPhone Use Pro」。顶部镜像提示由 iOS 显示，停止镜像会失去画面。
4. 访问 `http://127.0.0.1:7390/status`，应看到设备 `transport: airplay` 且 `bluetooth: true`。这只能说明连接就绪，还要完成下方实际操作验收。

## 验收与常见问题

- 拔掉 USB 后获取新截图、返回桌面、打开计算器并计算，核对新画面。不要只凭接口返回 ok 就判断成功。
- 输入框不显示屏幕键盘：聚焦后发送 `curl -X POST http://127.0.0.1:7390/key -H 'Content-Type: application/json' -d '{"key":"eject"}'`。这是显示/隐藏切换；本机已验证。
- 截图：`curl 'http://127.0.0.1:7390/screenshot?maxEdge=1200' -o screen.jpg`。
- 连续点击可能漏输入，逐步操作并观察画面。仅支持 US 键盘 ASCII 直接输入；不保证中文文本注入。
- 无接收器：检查 Wi-Fi、Mac 本地网络权限与日志。显示接收器但无画面：重新选择接收器，确认使用 Wi-Fi 接口，别沿用 USB 网络连接。
- 蓝牙已连但设备列表为空：仍需启动屏幕镜像。镜像正常但无法点击：检查 HID 订阅及辅助触控。
- 新连接未匹配时，普通输入接口不会自动移动指针来探测。先检查实时镜像与辅助触控，再显式运行 `curl -X POST http://127.0.0.1:7390/match -H 'Content-Type: application/json' -d '{}'`；仅在此匹配操作中，程序会用指针位置变化识别连接。无新鲜画面或证据不明确时，匹配会失败并保留已有映射。
- 长时间运行、锁屏恢复、跨网络、自动重连均未完成兼容性验收。Mac 必须保持运行；此交付不配置自动登录、自动启动或远程端口。

## 接入支持MCP的AI客户端

先完成安装、启动和手机连接；MCP进程通过本机HTTP接口调用已经运行的App，不会替你启动或配对手机。在支持stdio MCP的客户端中添加：

```json
{
  "mcpServers": {
    "iphone-use-pro": {
      "command": "/absolute/path/to/iphone-use-pro/scripts/mcp.sh"
    }
  }
}
```

把 `/absolute/path/to/iphone-use-pro` 换成你解压或克隆的**绝对路径**。路径可包含空格；不要填GitHub网址或 `~`。可用工具包括 `list_devices`、`screenshot`、`tap`、`long_press`、`swipe`、`type_text`、`press_key` 和 `home`。连接后先让AI读取设备列表和截图，再执行一次计算器操作并核对画面。MCP可控制已连接手机中的真实App，请只向你信任的本地客户端开放。

HTTP接口也可直接使用，见上方验收示例和 [接口参考](docs/UPSTREAM-README.md)。接口没有认证，仅限本机使用；不要用端口转发或反向代理把它暴露到网络。App运行时还会在局域网广播AirPlay接收器。

## 更新源码

退出App后执行 `git pull --ff-only`，重新运行 `./scripts/setup.sh`，再启动和连接。下载ZIP的用户重新下载新版并在新目录构建。仓库不包含个人配对数据或预编译App，不要把本机日志和截图提交到公开问题中。

## 第二台机器测试

在另一台 Apple Silicon / macOS 27+ Mac 解压代码，完成安装、权限、配对、无 USB 镜像、截图和计算器操作；再测试退出重启、锁屏解锁与断网重连。记录 Mac/iPhone 系统版本、每项实际结果及日志。未拿到第二台机器前，这一项不能标记通过。

## 源码与许可

主程序在 Sources，原生依赖在 third_party/mirrordeck-airplay，附带固定版本的 UxPlay 及本次 Wi-Fi 接口补丁。除附有独立许可声明的第三方组件外，本项目整体按 GNU GPL v3.0-only（SPDX：`GPL-3.0-only`）授权；第三方组件仍受各自随附许可证约束。分发时请保留源码与所有许可义务。原始 iPhone Use 的 MIT 声明在 [licenses/iPhoneUse-MIT.txt](licenses/iPhoneUse-MIT.txt)，所有上游出处与本地改动见 [AIRPLAY-NOTICE.md](AIRPLAY-NOTICE.md)。详见 LICENSE、licenses 和第三方目录的许可证。原项目操作接口说明见 docs/UPSTREAM-README.md；本次实现和验证记录见 WIRELESS.md。

## 0.3.0 优化记录

检查范围、删减项与验证见 [升级记录](docs/UPGRADE-0.3.0.md)。开发回归测试：先构建原生库，再运行 `./scripts/test.sh`。

## 截图分辨率

MCP 默认长边 800（当前手机输出 369×800）。小字时调用 screenshot 工具并传 `maxEdge: 1080`；随后点击按该设备上一次截图的尺寸换算。动作完成返回的截图恢复默认 800，请始终使用最新截图坐标。HTTP 直接调用时仍须显式匹配截图与点击的 maxEdge，例如截图 `?maxEdge=800`，点击 JSON 也传 `"maxEdge":800`。HTTP 未指定尺寸时保留原有完整尺寸行为。

本机计算器各10次样本：1080约61KB、中位14.6ms；800约41KB、中位12.8ms。仅测截图接口，未测 AI 推理耗时，不能据此承诺整体速度提升。已通过实际 MCP 默认图点击8、高清图点击9，画面从7变为789，验证尺寸切换坐标一致。

## 自适应等待与动作间隔

MCP 操作后不再固定睡眠 0.6 秒。它记录操作前的帧编号及低分辨率灰度特征，轮询新的帧，检测显著变化后等待至少约60毫秒的相似画面，最长等待1.2秒。状态栏和极小指针变化被尽量忽略；返回结果明确说明「画面稳定」或「超时」。这些都是启发式条件，不代表操作成功或页面加载完成，Agent仍需核对截图。未发生变化的合法操作可能等待到超时。

蓝牙每个完整动作之间默认留120毫秒空隙（同一动作内的HID报告间隔保持原值）。启动前设置 `IPHONE_USE_ACTION_GAP_MS=200 ./scripts/start.sh` 可改为200毫秒，允许0～1000；该配置在进程启动时读取，改变需重启。该间隔主要用于避免快速连续输入，不承诺更快的原始点击速度。

编译缓存 `.build` 可在完成构建/测试后删除；native/build 只需保留 libMirrorCore.dylib 供打包。重新构建会生成缓存，因此开发目录大小不代表 App 安装大小。

## 自动清理

安装/构建 App 成功后自动清理 Swift 编译缓存和原生编译中间文件；使用 `./scripts/test.sh` 运行回归测试也会在成功后清理。保留源码、App、libMirrorCore.dylib、配对信息和日志，手机控制无需重启。后续构建需要重新编译，因此会比保留缓存更慢。失败时缓存留下以便诊断。

开发时可设置 `IPHONE_USE_KEEP_BUILD_CACHE=1` 保留缓存。随时手动清理：`./scripts/clean-build-cache.sh`。直接执行 `swift test` 或 `swift build` 会绕过本项目的自动清理入口；不要在另一个构建正在进行时手动清理。
