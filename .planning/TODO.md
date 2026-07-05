# TODO

## 当前阶段必做

- [x] 跑通 `swift test`。
- [x] 跑通 `swift build`。
- [x] 跑通 `./script/build_and_run.sh --verify`。
- [x] 按截图标注调整 provider 头部、圆环线宽、Codex 标签/日期和 GLM MCP 卡片显示。
- [x] 修正 Codex token 汇总，真实 session 优先按 `total_token_usage` 差分，`last_token_usage` 作为兼容回退。
- [x] 对照 codexU 源码迁移 Codex app-server 额度读取、模型价格表、本月羊毛进度和圆环渐变。
- [x] 将 Codex / GLM 重置时间统一为本机时区 `MM-dd HH:mm`，不显示年份。
- [x] 去掉圆环中心“剩余”文案。
- [x] 今日起点按本机时区 00:00。
- [x] 修正和 codexU 的金额差异：有 SQLite rollout 来源时不再额外扫描全量 JSONL。
- [x] 羊毛卡片金额、进度条和 Plus / Pro100 / Pro200 刻度改为同卡片布局，刻度横向一行。
- [x] 羊毛进度 Plus / Pro100 / Pro200 点位改为 codexU 同款前 28% 订阅区间映射。
- [x] 所有卡片隐藏时，窗口最小宽度允许缩到圆环布局宽度。
- [x] 优化启动和刷新速度：Codex 日志改为关键行扫描 + 缓存，provider 刷新离开 MainActor，并发刷新 Codex/GLM。
- [x] 追认补齐最小 GSD v1.0.0 结构，GSD `init.manager` 可识别 Phase 1 已完成并验证通过。
- [x] 修复 code review 的 4 个 Warning：GLM force refresh、Codex 子进程超时、累计卡片全量口径、刷新间隔热更新。
- [x] 统一 1.0.0 发布元数据：Codex app-server client version、`CFBundleShortVersionString`、`CFBundleVersion`。
- [x] 补齐最小 milestone 文件：audit、roadmap archive、requirements archive、MILESTONES/STATE/PROJECT 收口。
- [x] 运行 `$gsd-complete-milestone 1.0.0`，归档 audit，压缩 ROADMAP，删除活动 REQUIREMENTS。
- [x] 运行 `$gsd-pause-work`，生成 `.planning/HANDOFF.json` 和 `.planning/.continue-here.md`。

## 后续 backlog

- [x] 运行 `$gsd-code-review 1 --depth=standard`。
- [x] 处理 `.planning/phases/01-initial-release/01-REVIEW.md` 中的 4 个 Warning。
- [x] 运行/补齐 `$gsd-audit-milestone 1.0.0` 等价的最小 milestone audit。
- [x] 完成初始 Git commit 和 `v1.0.0` tag。
- [ ] 开启 v1.1 release-prep milestone。
- [ ] 继续对照真实本机 Codex 数据做视觉数值抽样核对。
- [ ] 在有 GLM/ZAI 凭据的 App 环境中验证 GLM quota API 口径。
- [ ] 根据真实 provider 返回补齐更精确的错误分类和字段映射。
- [ ] 如还觉得慢，增加可视化刷新耗时日志，分别记录 app-server、SQLite、JSONL 扫描、GLM API 四段耗时。

## 不做或暂缓

- [ ] 不做 codexU 式桌面贴片和隐藏 Dock 行为。
