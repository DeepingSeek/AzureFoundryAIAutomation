# Azure Foundry AI Automation


> 本项目是在 [JungleWolf666/AzureFoundryAIAutomation](https://github.com/JungleWolf666/AzureFoundryAIAutomation)基础上做了修改与补充。

当前版本：`v1.1` · [更新记录](CHANGELOG.md) · [MIT License](LICENSE)

把 Azure AI Foundry 的开通流程从"逐个点门户"变成"填一张 CSV，运行几条命令"：创建订阅、创建 Foundry 账户和项目、批量部署模型、扩容配额、导出 Endpoint 与 API Key、查询订阅的 Quota Tier。

主推 **Windows + PowerShell**，脚本为 `Azure_Foundry_AI_Automation.ps1`。另有功能一致的 Bash 版本，见文末。

## 上手前必须知道的三件事

1. **先预演，再正式执行。** 所有阶段都支持 `-DryRun`，预演不创建、不修改任何 Azure 资源。正式执行前脚本会列出计划，并要求输入大写确认词。
2. **阶段 1（创建订阅）只适用于 EA 企业协议。** 订阅由 CSP 合作伙伴管理时，不要运行阶段 1，也不要运行菜单 7（全流程）。请合作伙伴创建订阅，把 `SubscriptionId` 填入 CSV，然后从阶段 2 开始。
3. **CSV 与输出可能包含凭据，不要提交到公开仓库。** 请复制一份 `*.local.csv` 作为自己的配置，这类文件已被 `.gitignore` 忽略。

## 第一次运行（PowerShell）

### 第 1 步：准备环境

- 安装 [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)（推荐；Windows PowerShell 5.1 也可运行）
- 安装 [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli-windows)，并确认 `az version` 可以执行
- 不需要 `jq`、Python 或 Az PowerShell 模块

### 第 2 步：获取脚本并建立本地配置

```powershell
git clone https://github.com/<你的账号>/<你的仓库>.git
cd <你的仓库>

# 复制一份本地配置，之后只编辑这份文件
Copy-Item .\Azure_Foundry_AI_Plan.csv .\Azure_Foundry_AI_Plan.local.csv
```

如果脚本是从压缩包下载的，先解除阻止：

```powershell
Unblock-File .\Azure_Foundry_AI_Automation.ps1
```

### 第 3 步：允许本次窗口运行脚本

Windows 默认禁止运行未签名脚本。下面的设置只对当前 PowerShell 窗口生效，关闭窗口即失效：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### 第 4 步：编辑 CSV

用 Excel 或任意文本编辑器打开 `Azure_Foundry_AI_Plan.local.csv`，替换所有占位值。已有订阅、从阶段 2 开始时，一行的最小示例如下：

```csv
BillingAccountName,EnrollmentAccountName,SubscriptionName,SubscriptionId,ResourceGroupName,FoundryResourceName,DefaultProjectName,Location,ModelNames,ModelVersion,ModelFormat,DeploymentType,DeploymentCapacityK
,,你的订阅名称,你的订阅GUID,rg-foundry-demo,demo-foundry-01-eus2-001,proj-demo-prod-eus2,eastus2,gpt-4o-mini,2026-01-01,OpenAI,GlobalStandard,
```

- `SubscriptionName` 必须与 Azure 门户中的订阅名称完全一致。
- `FoundryResourceName` 必须全局唯一，不要使用 `foundry-ai-01` 这类通用名。
- 模型版本请以 Azure 门户中该区域可用的版本为准。
- 字段的完整说明见下文 [CSV 配置](#csv-配置)。

### 第 5 步：预演

预演会先登录（终端会显示设备代码，按提示在浏览器完成登录），然后检查配置并列出计划，不修改任何资源：

```powershell
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage CreateFoundry -DryRun
```

如果提示 `53003 BlockedByConditionalAccess`，在命令后加上 `-BrowserLogin` 再试，见 [常见问题](#常见问题)。

### 第 6 步：正式执行

确认预演输出无误后，去掉 `-DryRun`。脚本会要求输入大写 `YES` 确认：

```powershell
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage CreateFoundry
```

创建完成后，部署模型：

```powershell
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage DeployModels -DryRun
.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage DeployModels
```

### 第 7 步：查看结果

| 目录 | 内容 |
|---|---|
| `delivery_reports\` | 交付清单，含 Endpoint 与部署明细（默认不含 API Key） |
| `results\` | 每个阶段的逐行结果，失败原因在 `ErrorMessage` 列 |
| `logs\` | 完整运行日志 |

> 不带 `-Stage` 运行时会进入交互式菜单，适合不熟悉参数的人。

## 常用命令速查

以下命令都在脚本所在目录执行，请把 `<TENANT-ID>` 替换为你的租户 ID。

| 场景 | 命令 |
|---|---|
| 交互式菜单 | `.\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv` |
| 预演任一阶段 | 在命令后加 `-DryRun` |
| 浏览器登录（设备代码被拦截时） | 在命令后加 `-BrowserLogin`，每次运行都要带 |
| 复用已登录的 Azure CLI 会话 | 在命令后加 `-SkipLogin`，脚本会校验租户是否一致 |
| 查看版本 | `.\Azure_Foundry_AI_Automation.ps1 -Version` |
| 查看帮助 | `.\Azure_Foundry_AI_Automation.ps1 -Help` |
| 盘点时包含旧版 Azure OpenAI 资源（`kind=OpenAI`） | 阶段 5 加 `-IncludeLegacyOpenAI`，默认不包含 |
| 批量生成 CSV（多个订阅） | `.\tools\New-PlanCsv.ps1 -SubscriptionName "sub-a,sub-b" -NamePrefix contoso -Location "eastus2,swedencentral" -ModelNames "gpt-4o"`，见 [批量生成 CSV](#批量生成-csv) |

## 我该运行哪个阶段

| 你的情况 | 运行顺序 |
|---|---|
| EA 企业协议，需要新建订阅 | 菜单 7，或 `-Stage All`（即阶段 1 → 2 → 3） |
| 订阅已经存在（包括 CSP 合作伙伴创建的） | `-Stage CreateFoundry`，再 `-Stage DeployModels` |
| 已有部署，还有剩余配额想用满 | `-Stage ScaleUpQuota` |
| 忘记在阶段 3 导出 API Key，或需要盘点所有账户 | `-Stage ExportCredentials` |
| 查询订阅的 Quota Tier | `-Stage QueryQuotaTier` |

各阶段的完整说明见 [阶段说明](#阶段说明)。

| 菜单 | `-Stage` | 作用 |
|---|---|---|
| 1 | `CreateSubscription` | 在 EA 下创建订阅，并回填 `SubscriptionId`（仅限 EA） |
| 2 | `CreateFoundry` | 创建资源组、Foundry 账户（AIServices）和默认 Project |
| 3 | `DeployModels` | 按剩余共享配额批量部署模型，并生成交付清单 |
| 4 | `ScaleUpQuota` | 把已有部署的容量扩到剩余配额上限 |
| 5 | `ExportCredentials` | 补导出 Endpoint 与 API Key，或按订阅全量盘点 |
| 6 | `QueryQuotaTier` | 查询订阅级 Azure OpenAI Quota Tier（预览 API） |
| 7 | `All` | 依次执行阶段 1 → 2 → 3（仅限 EA） |

## CSV 配置

列名与顺序必须严格一致：

```csv
BillingAccountName,EnrollmentAccountName,SubscriptionName,SubscriptionId,ResourceGroupName,FoundryResourceName,DefaultProjectName,Location,ModelNames,ModelVersion,ModelFormat,DeploymentType,DeploymentCapacityK
```

| 字段 | 说明 |
|---|---|
| `BillingAccountName` | EA Billing Account ID，仅阶段 1 使用 |
| `EnrollmentAccountName` | EA Enrollment Account ID（不是显示名称），仅阶段 1 使用 |
| `SubscriptionName` | 订阅名称。使用已有订阅时必须与 Azure 中的名称完全一致 |
| `SubscriptionId` | 阶段 1 创建后自动回填；使用已有订阅时手工填写 GUID |
| `ResourceGroupName` | 要创建或复用的资源组 |
| `FoundryResourceName` | Foundry 账户名，同时用于自定义子域名（2–64 位字母、数字、连字符，不支持下划线，全局唯一） |
| `DefaultProjectName` | 默认 Project 名称 |
| `Location` | 资源组、Foundry 账户和 Project 的区域 |
| `ModelNames` | 分号分隔的模型列表，见下表 |
| `ModelVersion` | 默认模型版本，格式 `YYYY-MM-DD` |
| `ModelFormat` | 默认模型格式，留空按 `OpenAI` |
| `DeploymentType` | 默认 SKU，留空按 `GlobalStandard` |
| `DeploymentCapacityK` | 留空表示用满剩余配额；填正整数表示固定容量（K TPM） |

### ModelNames 写法

每项省略的部分会回退到该行的 `ModelVersion` / `ModelFormat` / `DeploymentType`：

```text
gpt-5.6-sol                                    仅模型名
gpt-image-2:2026-04-21                         模型名 + 版本
FW-GLM-5.2::Fireworks                          模型名 + 格式
FW-GLM-5.2:::DataZoneStandard                  模型名 + SKU
FW-GLM-5.2:1:Fireworks:DataZoneStandard        模型名 + 版本 + 格式 + SKU
gpt-5.6-sol-dz=gpt-5.6-sol:::DataZoneStandard  自定义部署名 = 模型名 + SKU
```

### 常见配置场景

**同一模型使用多个 SKU。** 同一账户内部署名必须唯一，所以第二个 SKU 要用不同的部署名：

```csv
BILLING-ACCOUNT-ID,ENROLLMENT-ACCOUNT-ID,SUBSCRIPTION-DEMO,,rg-foundry-demo,demo-foundry-01-eus2-001,proj-demo-prod-eus2,eastus2,gpt-4o;gpt-4o-mini,2026-01-01,OpenAI,GlobalStandard,
BILLING-ACCOUNT-ID,ENROLLMENT-ACCOUNT-ID,SUBSCRIPTION-DEMO,,rg-foundry-demo,demo-foundry-01-eus2-001,proj-demo-prod-eus2,eastus2,gpt-4o-dz=gpt-4o:::DataZoneStandard,2026-01-01,OpenAI,DataZoneStandard,
```

**部署名必须与模型名完全一致。** 只能使用两个不同的 Foundry 账户，每个账户内使用裸模型名。

**同一订阅下多个账户或 Project。** 保持 `SubscriptionName` 与 `SubscriptionId` 相同，分别指定不同的 `FoundryResourceName` 和 `DefaultProjectName`。

### 命名建议

```text
FoundryResourceName   <客户简称>-foundry-<负载>-<区域>-<序号>     例：demo-foundry-01-eus2-001
DefaultProjectName    proj-<负载>-<环境>-<区域>                   例：proj-demo-prod-eus2
```

`FoundryResourceName` 在 Azure 全局范围内必须唯一。大小写会保留在资源名中，写入自定义子域名时统一转为小写。

## 批量生成 CSV

订阅较多时，手工逐行填写容易出错。`tools\New-PlanCsv.ps1` 按订阅列表生成 CSV：名称按序号生成，地区按订阅顺序轮询。它只写本地文件，不调用 Azure。

```powershell
.\tools\New-PlanCsv.ps1 -SubscriptionName "sub-a,sub-b,sub-c" `
    -SubscriptionId "<guid-a>,<guid-b>,<guid-c>" `
    -NamePrefix "contoso" -StartIndex 1 -Location "eastus2,swedencentral" `
    -ModelNames "gpt-4o;gpt-4o-mini" -ModelVersion "2026-01-01" `
    -OutputPath .\contoso.local.csv
```

- 列表参数用**逗号分隔**（`pwsh -File` 下 `"a","b"` 会被当成一个字符串）。
- 序号从 `-StartIndex` 开始，资源组、账户、Project 分别为 `<前缀>-rg-<序号>`、`<NamePrefix>-<序号>`、`<ProjectPrefix>-<序号>`。
- 输出文件已存在时会拒绝覆盖，确认覆盖请加 `-Force`。
- 生成后仍请先用 `-DryRun` 预演。

## 阶段说明

### 阶段 2：创建 Foundry 资源

- **创建任何资源之前先做模型预检**：确认该区域同时支持本行 `ModelNames` 中每个模型的名称、版本、格式和 SKU。不支持时该行记为 `NotStarted`，并在 `ErrorMessage` 中列出不支持的组合，不会留下只能部署失败的半成品资源。
- 读取模型列表失败时同样视为失败，不会误当作"全部支持"。

### 阶段 1：创建订阅（仅限 EA）

- 正式运行时要求输入大写 `EA` 确认，预演模式跳过该确认。
- `BillingAccountName` 与 `EnrollmentAccountName` 填写的是 ID 本身，不是完整资源 ID。在 Azure 门户的 **成本管理 + 计费** → **Enrollment accounts** 中查找。
- 订阅创建是租户级写操作，容易触发限流。遇到 429 时脚本会按 `Retry-After` 最多重试 6 次，并按待创建数量自动设置创建间隔：

| 待创建数量 | 自动间隔 |
|---|---|
| 1–20 | 10 秒 |
| 21–50 | 20 秒 |
| 51 及以上 | 30 秒 |

数量较多时可以分批执行。已成功的行会回填 `SubscriptionId`，重跑时自动跳过。需要手动指定间隔时使用 `-CreateDelaySeconds 30`。

### 阶段 3：部署模型与交付清单

- `DeploymentCapacityK` 留空时使用全部剩余配额；填写的数值超过剩余配额时，实际容量自动降到剩余配额。
- **同一配额池内的额度会被扣减。** 同一订阅、同一区域、同一模型和 SKU 的多个账户共享配额。前面的行部署后，后面的行会看到扣减后的剩余额度。剩余为 0 时记为 `NoQuota`，不会重复申请超出的容量。预演中同样会计入。
- 配额单位有两种：**TPM**（文本模型，显示为 `10 K TPM`、`3.333 M TPM`）和 **RPM**（按请求计费的模型，如 `gpt-image-*`、`dall-e`、`sora`，显示为 `10 RPM`）。RPM 由模型名关键字识别，遇到未覆盖的新模型请以门户显示为准。
- 执行完成后生成交付清单，每个项目一行：

| 列 | 说明 |
|---|---|
| `SubscriptionName` / `SubscriptionId` | 所属订阅 |
| `ResourceGroupName` / `FoundryResourceName` / `ProjectName` / `Location` | 资源定位 |
| `DeploymentCount` / `DeployedModels` | 部署数量与明细，格式 `部署名(模型名, SKU, 容量)` |
| `OpenAIEndpoint` | `https://<子域>.openai.azure.com/`，OpenAI SDK 与 AI 网关使用 |
| `ProjectEndpoint` | `https://<子域>.services.ai.azure.com/api/projects/<项目名>`，Foundry SDK 与 Agent 使用 |
| `ServicesEndpoint` | `https://<子域>.cognitiveservices.azure.com/`，Foundry Tools 使用 |
| `ApiKey` | 默认留空 |

API Key 是明文长期凭据，默认不导出。需要交付时，在提示处输入大写 `KEY`。包含 Key 的文件名带 `_WITH_KEY` 后缀。请通过安全渠道交付，交付后删除本地副本。

### 阶段 5：导出 Endpoint 与 API Key

运行后选择导出范围：

1. **仅导出 CSV 计划中的项目**：用于补导出阶段 3 时忘记输入 `KEY` 的情况。
2. **导出 CSV 订阅列表中所有 Foundry 账户与项目**：只信任 CSV 中明确填写的 `SubscriptionId`，资源组、账户和项目全部自动发现。未启用 Project 的旧版账户按账户级导出，`ProjectName` 留空。
   - 默认只扫描 `kind=AIServices` 的 Foundry 账户。加上 `-IncludeLegacyOpenAI`（Bash 为 `--include-legacy-openai`）后，同时包含旧版 Azure OpenAI 资源（`kind=OpenAI`），这类资源按账户级导出。

阶段 5 不支持预演模式。

### 阶段 6：Quota Tier 查询

只读取 CSV 中合法的 `SubscriptionId`，调用 ARM 预览 API `2025-10-01-preview`，输出 `QuotaTier`、`AssignmentDate`、`TierUpgradePolicy`、`Status` 和 `ErrorMessage`。

> 该接口返回的是订阅级 Quota Tier，不是区域或模型的已分配配额。预览 API 的字段可能调整。

## 输出文件

输出根目录默认为脚本所在目录，可用 `-OutputRoot` 指定：

```text
logs/                运行日志
results/             各阶段结果 CSV
csv_backups/         回填 SubscriptionId 前的 CSV 备份
delivery_reports/    交付清单
```

这些目录已被 `.gitignore` 忽略。

## 安全设计

- 所有阶段都支持预演；正式执行前显示计划并要求确认。
- 部署前校验订阅 ID、订阅名和租户三者一致，避免资源建到错误订阅。
- 已存在且配置一致的资源会跳过；配置冲突会记为失败，不会覆盖。
- 脚本不删除任何 Azure 资源。
- 回填 CSV 前先备份，并使用原子替换写入。
- API Key 只写入交付清单，不输出到终端或日志。

## 常见问题

### 登录失败：`53003 BlockedByConditionalAccess`

客户租户的 Entra 条件访问策略拦截了登录，常见原因是策略阻止了设备代码登录（脚本默认方式）。

1. 加上 `-BrowserLogin`，**每次运行都需要带上**：

   ```powershell
   .\Azure_Foundry_AI_Automation.ps1 -TenantId "<TENANT-ID>" -Csv .\Azure_Foundry_AI_Plan.local.csv -Stage CreateFoundry -DryRun -BrowserLogin
   ```

2. 若浏览器登录也被拦截，请客户管理员为你的账号或应用添加条件访问例外，或改用服务主体登录。服务主体登录后用 `-SkipLogin` 复用会话，脚本会校验会话租户与 `-TenantId` 是否一致。

### `CustomDomainInUse`

`FoundryResourceName` 已被全局占用。换一个更唯一的名称后重跑。

### `UserNotAuthorized`

当前账号无权在该 `BillingAccountName` / `EnrollmentAccountName` 下创建订阅，需要 Account Owner 确认权限。

### 订阅名不匹配

CSV 中的 `SubscriptionName` 与 Azure 实际名称不一致，脚本会拒绝执行。请改成门户中显示的真实名称。

### 区域没有配额项

目标区域没有该模型或该 SKU 组合，请更换区域或模型。

### `FlagMustBeSetForRestore`

同名的 Foundry 账户或项目曾被删除，仍处于软删除保护期内，无法直接重建。常见诱因：在门户删除资源组（会级联删除账户），或在账户只剩默认项目时删除该项目（实测会连账户一起删除）。

1. 确认是否处于软删除状态（先用 `az account set --subscription <订阅ID>` 切换到对应订阅）：

   ```powershell
   az cognitiveservices account list-deleted --output table
   ```

2. 确认不需要恢复后清除（**不可逆**）：

   ```powershell
   az cognitiveservices account purge --location <区域> --resource-group <资源组> --name <账户名>
   ```

   `purge` 返回成功不代表立即生效，可能需要等待几分钟到几十分钟。

3. `list-deleted` 为空后，重新运行阶段 2，再运行阶段 3。账户被删除后部署也会丢失，必须重新部署。

预防建议：不要在门户删除资源组、账户或唯一的项目。需要删除项目时，用 CLI 精确删除，不会级联删除账户：

```powershell
az cognitiveservices account project delete --name <账户名> --resource-group <资源组> --project-name <项目名>
```

## 账号权限

| 阶段 | 所需权限 |
|---|---|
| 1 | EA Enrollment Account 的创建订阅权限，以及 `Microsoft.Subscription/aliases` 写入权限 |
| 2 | 目标订阅读取权限、资源组创建与读取、`Microsoft.CognitiveServices` 注册、Cognitive Services 账户与 Project 创建 |
| 3 / 4 | 目标订阅切换与读取、Foundry 账户读取，`accounts/deployments/read` 与 `write`，`locations/usages/read` |
| 5 | 账户读取与 `accounts/listKeys/action`（无此权限时 `ApiKey` 列留空，不中断） |
| 6 | 读取订阅 Quota Tier 的权限 |

## 使用 AI 助手（Agent Skill）

仓库内附带一个 Claude Code Skill：`.claude/skills/azure-foundry-automation/`。用 Claude Code 打开本仓库后，助手会自动识别它，帮你：

- 确认订阅类型（EA、CSP 或已有订阅），选择正确的阶段顺序；
- 生成或检查 `*.local.csv`，必要时调用 `tools\New-PlanCsv.ps1` 批量生成；
- 先预演，解读结果 CSV，按错误信息给出排查建议；
- 在你批准后，告诉你该输入的命令。

助手**不会替你输入** `YES`、`EA`、`KEY`，也不会在对话中输出 API Key。正式执行前，它会请你确认。

Skill 的参考资料在 `references/` 下：`csv-guide.md`（CSV 字段与写法）、`troubleshooting.md`（错误与解决办法）。

## Bash 版本（可选）

Bash 版本与 PowerShell 版本功能一致，参数为 `--` 形式，例如：

```bash
bash Azure_Foundry_AI_Automation.sh --tenant-id "<TENANT-ID>" --csv ./Azure_Foundry_AI_Plan.local.csv --stage DeployModels --dry-run
```

- 需要 Bash 3.2+、Azure CLI、`jq`，以及 Python 3（脚本依次探测 `python3` 和 `python`；Windows 上通常只有 `python`）。
- 在 Windows 上可通过 Git Bash 运行。

## 测试

仓库提供离线烟雾测试，使用假的 `az`（`tests/fake_az.sh`）验证关键路径，不访问 Azure。两套测试覆盖相同的场景：

```powershell
# PowerShell 版（主推）：需要 Git for Windows，用于运行假 az
pwsh -File .\tests\smoke.ps1
pwsh -File .\tests\smoke.ps1 -BashPath "C:\Program Files\Git\bin\bash.exe"   # Git 不在默认位置时

# Bash 版
bash tests/smoke.sh
```

覆盖内容：参数校验；阶段 1 的失败信息回传与停止；阶段 2 的资源组失败、区域模型预检；阶段 3 的同一配额池记账、模型列表失败；阶段 4 的部署列表失败；阶段 5 的旧版 OpenAI 开关；批量生成 CSV 的序号与地区轮询。

这些测试不覆盖成功路径（假 `az` 没有状态），因此修改后仍请用测试订阅先做预演。

## 目录结构

```text
.
├── Azure_Foundry_AI_Automation.ps1   # PowerShell 版本（主推）
├── Azure_Foundry_AI_Automation.sh    # Bash 版本
├── Azure_Foundry_AI_Plan.csv         # 脱敏配置模板，请复制为 *.local.csv 后使用
├── CHANGELOG.md                      # 版本更新记录
├── LICENSE                           # MIT
├── README.md
├── tools/
│   └── New-PlanCsv.ps1               # 批量生成 CSV
├── .claude/
│   └── skills/
│       └── azure-foundry-automation/ # AI 助手 Skill（SKILL.md + references/）
└── tests/
    ├── smoke.ps1                     # PowerShell 离线烟雾测试
    ├── smoke.sh                      # Bash 离线烟雾测试
    ├── fake_az.sh                    # 测试用假 az
    └── fixtures/                     # 测试用 CSV 与 JSON
```
