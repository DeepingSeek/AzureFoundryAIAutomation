# Copilot 仓库指令

本仓库用于 Azure AI Foundry 的开通与交付自动化（PowerShell 主脚本 `Azure_Foundry_AI_Automation.ps1`）。完整说明见 `AGENTS.md`，以下是修改代码和回答问题时需要遵守的要点。

## 安全规则

- 不替用户输入 `YES`、`EA`、`KEY` 或阶段 5 的菜单选项，这些只能由用户在终端输入。
- 任何会修改 Azure 的命令，先给出 `-DryRun` 版本，由用户确认后再给出正式命令。
- 阶段 1（`CreateSubscription`）与 `All` 仅适用于 EA 企业协议，不要建议用于 CSP 或已有订阅。
- 不在回答、代码或日志中写入真实的订阅 ID、账单账户 ID 或 API Key。使用占位符，如 `<TENANT-ID>`。
- 不修改 `Azure_Foundry_AI_Plan.csv` 模板，示例配置放在 `*.local.csv`。

## 代码约定

- 修改 `Azure_Foundry_AI_Automation.ps1` 时，同步检查 `Azure_Foundry_AI_Automation.sh` 是否需要相同改动。两个版本功能需保持一致。
- 修改后运行 `pwsh -File .\tests\smoke.ps1`（需要 Git for Windows）和 `bash tests/smoke.sh`，两者都应通过。
- 结果状态值（`Succeeded`、`WhatIf`、`NoQuota`、`Failed`、`NotStarted` 等）保持一致。
- 在 `CHANGELOG.md` 的"未发布"条目中记录修改。
