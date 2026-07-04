# .planning/agents

多 agent 协作目录。

## 应该放什么

- 放 agent 角色分配、子任务拆分、并行执行结果和合并结论。
- 适合 Codex、Hermes Agent、GStack、subagent 编排等场景。
- 每个 agent 的输出应包含任务范围、改动文件、验证结果和剩余风险。
- 不要让某个 agent 的私有状态成为唯一真相，关键结果要回写到 HANDOFF.md 或 TODO.md。

## 给人类的阅读建议

先看本文件了解边界，再进入具体文件。目录内如果出现难以归类的内容，应优先移动到更合适的位置，而不是继续堆积。

## 给 agent 的执行建议

修改本目录前先确认上游入口、下游调用和验证命令。完成后把重要结论写回 `.planning/HANDOFF.md` 或相关文档。
