# 额度雷达 / Quota Radar

额度雷达是一个正常形态的 macOS SwiftUI App，用来在一个可调整大小的窗口里查看 Codex 和 GLM / ZAI coding plan 的额度、重置时间和本机 token 使用情况。

它不是桌面贴片，也不是隐藏 Dock 的菜单栏小工具：应用会显示在程序坞，有系统菜单栏，窗口左上角保留关闭、最小化和缩放按钮。

## 快速开始

构建：

```bash
swift build
```

测试：

```bash
swift test
```

构建并以 `.app` bundle 方式运行：

```bash
./script/build_and_run.sh
```

验证进程启动：

```bash
./script/build_and_run.sh --verify
```

## 数据来源

- Codex：优先读取本机 `~/.codex` token/session 数据，并尝试调用本机 Codex app-server 的额度接口。
- GLM / ZAI：内置参考 `glm-plan-usage` 的读取方式，使用 `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_BASE_URL` 调用 quota API；设置页可手动补充。

所有数据都在本机读取；首版不会上传 usage、token、线程或凭据。

## 项目结构

```text
Sources/QuotaRadar/
├─ App/        # SwiftUI App 入口和正常 Dock App 激活
├─ Models/     # Provider 快照、卡片、额度窗口等数据模型
├─ Services/   # Codex / GLM 数据源和解析器
├─ Stores/     # 设置和刷新状态
├─ Support/    # 格式化、颜色、JSON 提取工具
└─ Views/      # 主窗口、Provider 面板、设置页
```
