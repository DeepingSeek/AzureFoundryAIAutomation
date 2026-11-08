# AGENTS.md

本文件给 AI 编码助手（Codex、GitHub Copilot、Claude Code 等）阅读，说明本仓库的用途、命令和安全规则。

## 项目用途

用 CSV 驱动 Azure AI Foundry 的开通与交付：创建订阅（仅 EA）、创建 Foundry 账户与项目、批量部署模型、扩容配额、导出 Endpoint 与 API Key（交付清单）、查询订阅 Quota Tier。

- 主脚本：`Azure_Foundry_AI_Automation.ps1`（PowerShell，主推）与 `Azure_Foundry_AI_Automation.sh`（Bash，功能一致）
- 配置模板：`Azure_Foundry_AI_Plan.csv`（脱敏模板，不可直接用于正式部署）
- 批量生成 CSV：`tools/New-PlanCsv.ps1`
- 客户用的 Skill 与参考资料：`.claude/skills/azure-foundry-automation/`

## 常用命令

```powershell
# 版本与帮助
.\Azure_Foundry_AI_Automation.ps1 -Version
.\Azure_Foundry_AI_Automation.ps1 -Help

# 预演（不修改 Azure）
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage CreateFoundry -DryRun

# 离线测试（不访问 Azure，需要 Git for Windows 运行假 az）
pwsh -File .\tests\smoke.ps1
bash tests/smoke.sh
```

修改脚本后必须运行两套离线测试，二者都应全部通过。

## 安全规则（必须遵守）

- 不替用户输入确认词：`YES`、`EA`、`KEY` 以及阶段 5 的菜单选项只能由用户在终端输入。
- 先预演，再正式执行。正式执行前必须得到用户明确批准。
- 阶段 1（`CreateSubscription`）与 `All` 只适用于 EA 企业协议。CSP 或订阅已存在时不要运行。
- 不在对话、日志或提交中输出 API Key、真实订阅 ID、账单账户 ID。真实配置只放在 `*.local.csv`（已被 `.gitignore` 忽略）。
- 不修改 `Azure_Foundry_AI_Plan.csv` 模板。
- 脚本不删除 Azure 资源。若用户要求清理，只给出步骤，由用户执行。
- 阶段 5 不支持预演模式，执行前需告知用户。

## 代码约定

- 两个主脚本的功能必须保持一致。修改一版时同步另一版，并在 `CHANGELOG.md` 的"未发布"条目中记录。
- 测试夹具使用假 `az`（`tests/fake_az.sh`），新增用例时补充对应的假接口。
- 阶段结果以 CSV 输出到 `results/`，状态值（如 `Succeeded`、`WhatIf`、`NoQuota`、`Failed`、`NotStarted`）需保持一致。
- Bash 脚本需使用 LF 行尾（`.gitattributes` 已约定）。

## 参考文档

- 客户场景的操作步骤与解读结果：`.claude/skills/azure-foundry-automation/SKILL.md`
- CSV 字段与写法：`.claude/skills/azure-foundry-automation/references/csv-guide.md`
- 错误与排查：`.claude/skills/azure-foundry-automation/references/troubleshooting.md`
