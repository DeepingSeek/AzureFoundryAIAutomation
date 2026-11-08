---
name: azure-foundry-automation
description: 用本仓库的 Azure_Foundry_AI_Automation.ps1 开通和管理 Azure AI Foundry：生成 CSV 配置、预演、创建 Foundry 账户与项目、批量部署模型、扩容配额、导出 Endpoint 与 API Key（交付清单）、查询订阅 Quota Tier。当用户提到 Azure Foundry、AI Foundry、开通 Foundry、部署模型、Azure OpenAI 批量部署、配额扩容、导出 endpoint 或 API Key、交付清单、Quota Tier、EA 订阅开通、Foundry 批量交付时使用。
---

# Azure Foundry 自动化助手

帮助用户用本仓库的 PowerShell 脚本完成 Azure AI Foundry 的开通与交付。你负责**规划、生成配置、预演、解读结果和交付指引**；真正的 Azure 资源变更只在用户明确批准后，由用户亲自确认执行。

## 先确认的三件事

1. **订阅类型**：EA 企业协议，还是 CSP 合作伙伴管理，还是订阅已经存在？
   - EA：可以运行阶段 1（`CreateSubscription`）或菜单 7（`All`）。
   - CSP 或订阅已存在：**绝不运行阶段 1 或 `All`**。从阶段 2 开始，`SubscriptionId` 由用户手工填入 CSV。
2. **范围**：多少个订阅、哪些区域、哪些模型（名称、版本、SKU）、每个订阅要几个 Foundry 账户。
3. **环境**：`az version`、`pwsh --version` 是否可用；是否已登录（脚本默认设备代码登录，被条件访问拦截时加 `-BrowserLogin`）。

信息不全时先问清楚，不要猜测订阅名、账户名或模型版本。

## 硬性规则（任何情况下都要遵守）

- **不替用户输入确认词**。`YES`、`EA`、`KEY` 以及阶段 5 的菜单选项必须由用户自己在终端输入。你可以告诉用户"此时终端会要求输入 YES，请你确认后输入"。
- **先预演，再正式执行**。每个会改动 Azure 的阶段都先加 `-DryRun`，把结果给用户看，等用户明确说"可以正式执行"后再去掉 `-DryRun`。
- **不修改模板，不提交真实配置**。在 `Azure_Foundry_AI_Plan.csv` 的副本 `*.local.csv` 中工作；真实订阅 ID、账单账户 ID 不写入任何会被提交的文件。
- **不在对话中输出 API Key**。`ApiKey` 只写入 `delivery_reports\*_WITH_KEY.csv`，提醒用户通过安全渠道交付，并在交付后删除本地副本。
- **不删除资源**。脚本本身不删除资源；如果用户要求清理，只给出步骤，由用户自己执行。
- **阶段 5 不支持预演**。需要先告诉用户这一点。

## 标准流程

### 第 1 步：生成 CSV

- 少量订阅：直接按 `references/csv-guide.md` 的字段说明写 `*.local.csv`。
- 批量（约 3 个以上订阅）：用 `tools\New-PlanCsv.ps1` 生成，名称按序号、地区按订阅轮询：

```powershell
.\tools\New-PlanCsv.ps1 -SubscriptionName "sub-a,sub-b,sub-c" -SubscriptionId "<guid-a>,<guid-b>,<guid-c>" `
    -NamePrefix "contoso" -StartIndex 1 -Location "eastus2,swedencentral" `
    -ModelNames "gpt-4o;gpt-4o-mini" -ModelVersion "2026-01-01" -OutputPath .\contoso.local.csv
```

注意：`pwsh -File` 下列表参数用**逗号分隔的字符串**，不要写成 `"a","b"`。

### 第 2 步：按顺序预演

按用户场景选择阶段（见下表），逐个预演：

```powershell
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\contoso.local.csv -Stage CreateFoundry -DryRun
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\contoso.local.csv -Stage DeployModels -DryRun
```

预演后读取 `results\` 下对应的结果 CSV，把关键结果告诉用户（见下文"解读结果"）。预演出现 `Failed`、`NotStarted`、`NoQuota` 时，先解决原因再进入正式执行。

### 第 3 步：请用户批准后正式执行

告诉用户要执行的命令（去掉 `-DryRun`），说明终端会要求输入 `YES`，由用户自己输入。正式执行后读取结果 CSV 并汇报。

### 第 4 步：交付

- 阶段 3 结束时终端会询问是否包含 API Key（默认不包含）。是否输入 `KEY` 由用户决定。
- 需要补导出时用阶段 5：终端会让用户选择范围 1（CSV 计划中的项目）或 2（订阅内全量盘点）。盘点需要旧版 Azure OpenAI 资源时加 `-IncludeLegacyOpenAI`。
- 交付清单在 `delivery_reports\`，列为 `OpenAIEndpoint`、`ProjectEndpoint`、`ServicesEndpoint`、`DeployedModels` 等。

## 按场景选择阶段

| 用户情况 | 运行顺序 |
|---|---|
| EA，需要新建订阅 | 阶段 1 `CreateSubscription` → 阶段 2 `CreateFoundry` → 阶段 3 `DeployModels`（或菜单 7） |
| 订阅已存在（含 CSP） | 阶段 2 `CreateFoundry` → 阶段 3 `DeployModels` |
| 已部署过，想用满剩余配额 | 阶段 4 `ScaleUpQuota` |
| 忘了导出 Key，或要盘点所有账户 | 阶段 5 `ExportCredentials` |
| 查订阅的 Quota Tier | 阶段 6 `QueryQuotaTier` |

## 解读结果

结果文件在 `results\`，按阶段命名（`stage1_…`、`stage2_…` 等）。常见状态：

| 状态 | 含义 | 你该怎么做 |
|---|---|---|
| `Succeeded` | 已完成 | 无需处理 |
| `WhatIf` | 预演计划 | 确认后再正式执行 |
| `SkippedExisting` | 已存在且配置一致 | 无需处理 |
| `NoQuota` | 剩余配额为 0（含同一配额池内先前行已用完） | 申请配额，或减少其他行的容量 |
| `Failed` | 失败，`ErrorMessage` 列有原因 | 按 `references/troubleshooting.md` 排查 |
| `NotStarted` | 因前置检查失败，未创建任何资源 | 先修复 `ErrorMessage` 中的问题 |
| `Conflict` / `AmbiguousExisting` | 已有资源与计划冲突（PowerShell 版通常记为 `Failed`，原因在 `ErrorMessage`） | 停下来询问用户，不要覆盖 |

汇报时用自己的话概括：成功几项、失败几项、失败原因是什么、下一步需要用户做什么。

## 常用参数

| 参数 | 用途 |
|---|---|
| `-TenantId "<TENANT-ID>"` | 必填，客户租户 ID |
| `-Csv <路径>` | 指定配置文件（默认是模板，建议用 `*.local.csv`） |
| `-DryRun` | 预演，不改 Azure |
| `-BrowserLogin` | 设备代码被条件访问拦截时使用，**每次运行都要带** |
| `-SkipLogin` | 复用已登录的 Azure CLI 会话（会校验租户） |
| `-OutputRoot <路径>` | 日志、结果、交付清单的输出目录 |
| `-IncludeLegacyOpenAI` | 仅阶段 5 盘点时加入旧版 `kind=OpenAI` 资源 |

## 更多参考

- `references/csv-guide.md`：CSV 字段、`ModelNames` 写法、常见配置场景。
- `references/troubleshooting.md`：错误信息与解决办法（登录 53003、软删除、配额、区域不支持模型等）。
