# CLAUDE.md

Claude Code 会自动读取本文件。项目总体说明和命令见 [AGENTS.md](AGENTS.md)。

## 使用本仓库时

- 客户场景的操作流程由 Skill `azure-foundry-automation` 提供（位于 `.claude/skills/azure-foundry-automation/`）。涉及开通、部署、导出、配额的问题，优先使用该 Skill。
- 任何会修改 Azure 的命令，先给出 `-DryRun` 版本。不替用户输入 `YES`、`EA`、`KEY` 或菜单选项。
- 不在对话中输出 API Key、真实订阅 ID 或账单账户 ID。
- 不修改 `Azure_Foundry_AI_Plan.csv` 模板，使用 `*.local.csv`。
- 修改脚本后，运行 `pwsh -File .\tests\smoke.ps1` 与 `bash tests/smoke.sh`。
