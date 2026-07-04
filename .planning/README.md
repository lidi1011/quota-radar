# .planning

协作状态目录。

## 应该放什么

- 放当前计划、交接、阶段状态、agent 执行记录和人工待办。
- 这是避免新会话失忆的核心目录。
- 短期状态、当前阻塞和下一步建议都应该写在这里。
- agent 接手项目时，应先读 HANDOFF.md，再决定行动。

## 给人类的阅读建议

先看本文件了解边界，再进入具体文件。目录内如果出现难以归类的内容，应优先移动到更合适的位置，而不是继续堆积。

## 给 agent 的执行建议

修改本目录前先确认上游入口、下游调用和验证命令。完成后把重要结论写回 `.planning/HANDOFF.md` 或相关文档。

## 工具分区

- `gsd/`：GSD 阶段、里程碑、pause/resume 和项目推进记录。
- `superpowers/`：TDD、debugging、verification、code review 等工程纪律记录。
- `matt/`：追问、领域建模、架构加深候选和设计边界记录。
- `product-design/`：产品 brief、UX audit、视觉探索、原型和设计 QA 记录。
- `agents/`：多 agent 分工、执行结果和交接记录。
