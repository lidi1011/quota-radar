# Agent Collaboration Rules

本文件是给 Codex、Hermes Agent、Claude Code、GSD、Superpowers、GStack、多 agent 编排器以及其他自动化开发工具看的项目规则。

## 开始工作前

1. 读取 `README.md`，理解项目目标和启动方式。
2. 读取本文件，遵守协作规则。
3. 读取 `.planning/HANDOFF.md`，确认当前状态和下一步。
4. 如果存在 `DESIGN.md`，涉及 UI、前端、视觉实现或设计 token 时必须先读取它。
5. 执行 `git status`，不要覆盖用户或其他 agent 未提交的改动。
6. 如果存在 `.planning/USER_REQUIRED.md`，先检查是否有必须由人类完成的事项。

## 修改代码时

- 优先遵循现有代码风格和目录结构。
- 不做无关重构。
- 不把密钥、token、cookie、私有账号信息写进仓库。
- 新增复杂能力时，同步更新 `docs/` 或 `.planning/` 中对应说明。
- 生成物放入 `artifacts/`，临时文件放入 `tmp/`。

## 验证规则

- 修复 bug 后尽量补充或更新测试。
- 优先使用 `scripts/test.*`、`npm test`、`pytest`、`cargo test`、`swift test` 等项目已有验证入口。
- 如果无法运行测试，在交接中写清楚原因和剩余风险。

## 交接规则

每次暂停、换 agent、切换会话或完成一个阶段时，更新：

- `.planning/HANDOFF.md`
- `.planning/TODO.md`
- `.planning/USER_REQUIRED.md`，如果有人类必须处理的事项
- `.planning/phases/`，如果涉及阶段推进

交接必须包括：当前目标、已完成内容、未完成内容、阻塞点、已验证命令、下一步建议。

## 工具适配建议

- GSD：可以把阶段、pause/resume、milestone 记录映射到 `.planning/gsd/` 或 `.planning/phases/`。
- Superpowers：可以把 TDD、debugging、verification 过程沉淀到 `.planning/superpowers/`。
- Matt skills：可以把追问、领域建模、架构加深候选写入 `.planning/matt/`，长期决策同步到 `docs/decisions/`。
- Product Design：可以把产品 brief、UX audit、设计 QA 记录写入 `.planning/product-design/`，截图和原型产物放入 `artifacts/product-design/`。
- GStack 或多 agent 编排：可以把子任务分配、agent 角色和执行结果写入 `.planning/agents/`。
- 所有工具的内部状态都可以保留，但不能替代 `README.md`、`AGENTS.md`、`.planning/HANDOFF.md` 这些项目级真相。
