# Handoff

## 当前目标

额度雷达 v1.0.0 已完成。当前目标是保留清晰的 milestone 完成态，并在需要时开启 v1.1 release-prep milestone。

## 最近完成

- 初始化 SwiftPM App 结构。
- 添加 Codex / GLM provider 抽象、解析器、设置存储和主窗口 UI。
- 添加 `script/build_and_run.sh` 和 Codex Run 按钮配置。
- 去掉窗口内顶部大标题区，窗口内容从 provider 面板开始。
- GLM provider 改为内置读取 GLM/ZAI quota API，不再依赖本机安装 `glm-plan-usage` 命令。
- 羊毛进度改为普通卡片，和其他卡片一起参与响应式网格缩放。
- 设置页重做为卡片式布局；GLM API token/base URL 已移动到 GLM tab。
- 生成的 Quota Radar logo 已加入 App 资源，并由运行脚本打包进 `.app` bundle。
- 已用 `/Users/lidi/Desktop/glm-api` 测试 GLM quota API：HTTP 200，返回 5h token、weekly token 和 MCP/time quota。
- 已验证本机 Codex session JSONL 中存在 `rate_limits`，App 现在优先从该字段读取 Codex 额度。
- 按 UI 标注移除 provider 标题旁说明和标题下数据源说明；Codex/GLM 面板只保留 provider 名称。
- 统一额度圆环内外两层线宽；Codex / GLM 窗口标签统一为“5 小时”和“7 天”，重置时间按本机时区显示为 `MM-dd HH:mm`，不显示年份。
- 对照 codexU 源码后调整 Codex 口径：额度优先走 `codex app-server` 的 `account/rateLimits/read` JSON-RPC，失败再回退 session JSONL 中的 `rate_limits`。
- 对照 codexU 源码后调整 Codex 金额口径：优先从 `state_5.sqlite` 读取 `rollout_path + model`，按 session 内 `total_token_usage` 做相邻事件 delta，再按模型价格表计算 token 成本；如果 SQLite 来源存在，不再额外扫描全量 JSONL，避免比 codexU 多计。
- 今日、近 7 天、本月窗口使用本机时区日界线；今日起点为本机时区 00:00。
- token 主数字按 codexU 的 visible total 口径：优先使用 `total_tokens`，否则使用输入 + 输出拆分合计。
- 羊毛进度改为本月 Codex API 等效金额，满额值沿用 codexU 的 `200M tokens/天 * 30 天` 和 30%/50%/20% mix，约 `$46.5K`。
- 羊毛卡片进度条改为 codexU 同款分段映射：Plus / Pro100 / Pro200 三个点位落在前 28% 的订阅区间，刻度横向排成一行。
- 圆环加入从主色到浅色的渐变，并在剩余额度降低时增加浅色混合比例。
- 圆环中心去掉“剩余”文案。
- 所有卡片隐藏时，provider 面板不再渲染空 dashboard 区域，主窗口最小宽度降到圆环布局可用宽度。
- GLM MCP 卡片改为主值显示百分比，说明行显示 `已用/总量`。
- 定位并优化启动/刷新慢的问题：本机 `~/.codex` session/archived JSONL 约 438MB、149 个 JSONL，SQLite 指向 147 个有效 rollout；旧实现每次刷新会整文件读入并解析，且 provider 协议挂在 MainActor 上，导致启动和点击刷新明显慢于 codexU。
- 实测 Codex `account/rateLimits/read` app-server 约 0.14s，147 个 rollout 的 `grep token_count` 冷扫描约 2.7s；慢点主要来自 token/金额汇总日志扫描，不是额度接口本身。
- Codex token 汇总改为只用 `grep token_count` 抽取关键行，并按文件大小/修改时间做进程内缓存；缓存命中后刷新不再重复扫描未变化 session。
- Codex / GLM provider 从 MainActor 解耦，`refreshAll` 改为并发刷新两个 provider，谁先完成谁先显示。
- GLM quota API 对确定性 ProviderError 不再做 3 次重试，避免 token 缺失、HTTP 非 200、API 返回失败时白等。
- 追认补齐最小 GSD v1.0.0 结构：`.planning/PROJECT.md`、`REQUIREMENTS.md`、`ROADMAP.md`、`STATE.md`、`MILESTONES.md`、`config.json`，以及 Phase 1 的 `01-01-PLAN.md`、`01-01-SUMMARY.md`、`01-01-VERIFICATION.md`。
- GSD 现在可以识别 Phase 1：`init.manager` 显示 Phase 1 `phase_complete=true`、`verification_status=passed`、`all_complete=true`。
- 已运行 `$gsd-code-review 1 --depth=standard` 的 inline fallback 审查，并生成 `.planning/phases/01-initial-release/01-REVIEW.md`。审查结果：0 Critical、4 Warning、1 Info。
- 已修复 `01-REVIEW.md` 中所有 4 个 Warning 和 1 个 Info，并生成 `.planning/phases/01-initial-release/01-REVIEW-FIX.md`：GLM force refresh 现在绕过缓存；Codex app-server/sqlite/grep 子进程均有超时；Codex “累计”不再截断最近 800 个 source；自动刷新间隔修改会立即重建定时器；版本元数据统一为 `1.0.0`。
- 已补齐最小 milestone 收口文件：`.planning/milestones/v1.0.0-MILESTONE-AUDIT.md`、`.planning/milestones/v1.0.0-ROADMAP.md`、`.planning/milestones/v1.0.0-REQUIREMENTS.md`，并同步更新 `MILESTONES.md`、`ROADMAP.md`、`PROJECT.md`、`STATE.md`、`TODO.md`。
- 已运行 `$gsd-complete-milestone 1.0.0`：audit 已移动到 `.planning/milestones/v1.0.0-MILESTONE-AUDIT.md`，当前 `ROADMAP.md` 已压缩为 milestone 摘要，活动 `.planning/REQUIREMENTS.md` 已删除，后续新需求应由 `$gsd-new-milestone` 重新生成。

## 当前状态

- 分支：master。
- 最近验证（2026-07-05 03:12 fresh run）：`swift test` 通过，14 个测试、0 failures；`swift build` 通过，exit 0；`./script/build_and_run.sh --verify` 通过，exit 0，并确认 QuotaRadar 进程可启动。`dist/QuotaRadar.app/Contents/Info.plist` 已确认包含 `CFBundleShortVersionString=1.0.0` 和 `CFBundleVersion=1`。
- 当前阻塞：GLM quota API 仍需要在有 GLM/ZAI 凭据的 App 环境中继续验证；无凭据时 UI 会显示错误态。
- 暂停交接：`.planning/HANDOFF.json` 和 `.planning/.continue-here.md` 已记录 v1.0.0 完成态；下一次恢复应从 `$gsd-new-milestone` 开始。

## 下一步

1. 后续开启 v1.1 release-prep milestone。
2. GLM 真凭据验证仍需用户提供 token。
3. GitHub/App Store 打包签名策略放到 v1.1 里处理。

## 风险和注意事项

- 不要只依赖聊天记录恢复上下文。
- 新 agent 接手前先执行 `git status`，再阅读本文件。
- 不要把 GLM token、cookie 或私有账号信息写进仓库。
- 不要因为 pause handoff 提交而移动 `v1.0.0` tag；tag 应保持指向 milestone completion 提交。
