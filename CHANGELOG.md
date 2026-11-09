# 更新记录

## [未发布]

### 修复

- 同一配额池的额度记账：同一订阅、区域、模型和 SKU 的多个账户共享配额，部署（含预演）成功后扣减已分配额度，后续行不再沿用旧的剩余额度（Bash 与 PowerShell 版）。
- PowerShell 版阶段 1 回填 CSV 失败时立即停止本阶段，并在结果中保留新订阅 ID。此前会继续创建下一个订阅，重跑时可能重复创建（Bash 版已是此行为）。
- Bash 版配额缓存在子 shell 中写入而丢失，缓存从未生效；现改为全局变量返回，每个配额只请求一次。
- Bash 版在 Windows 上 Python 输出带 `\r`，导致 SKU、订阅 ID 无法匹配；所有 Python 输出统一去掉回车。

### 新增

- 阶段 2 在创建任何资源之前做区域模型预检：区域不支持的模型组合（名称、版本、格式或 SKU）记为 `NotStarted` 并说明原因（Bash 与 PowerShell 版）。模型列表读取失败时同样视为失败。
- `tools/New-PlanCsv.ps1`：按订阅列表批量生成 CSV，序号自动生成，地区按订阅轮询。
- 阶段 5 新增 `-IncludeLegacyOpenAI`（Bash 为 `--include-legacy-openai`），可选择纳入旧版 Azure OpenAI 资源（`kind=OpenAI`）。默认不包含。
- `-AgreementType EA|CSP`（Bash 为 `--agreement-type`，默认 EA）：CSP 客户运行阶段 1 或 `All` 时，在登录前拒绝执行（两版一致）。
- 新增只读预检阶段 `Preflight`（PowerShell 菜单 8，Bash 菜单 8）：检查订阅可见性与状态、区域、Provider 注册、模型组合、已有部署与配额，并按阶段 3 的规则模拟配额分配。输出 `stage0_preflight`；配额不足的行写入 `quota_request`，列出所需容量、剩余容量、缺口与原因。
- `tests/smoke.ps1`：PowerShell 离线烟雾测试，与 Bash 版覆盖相同场景。
- `.claude/skills/azure-foundry-automation/`：AI 助手 Skill，附 CSV 指南与排错指南。
- AI 工具配置：`AGENTS.md`（Codex、Copilot 等读取）、`CLAUDE.md`（Claude Code）、`.github/copilot-instructions.md`（GitHub Copilot）。三者共享同一套安全规则。

### 测试

- `tests/smoke.sh` 扩展到 30 项，`tests/smoke.ps1` 为 26 项，均离线运行。
- 假 `az` 增加模型列表、配额 usage 和旧版账户接口。

## [1.1] - 2026-11-08

### 修复

- Bash 版自动探测 `python3` 或 `python`（需为 Python 3），修复 Windows 环境只有 `python` 时脚本启动即报“缺少 python3”的问题。
- Bash 版 Python 输出统一为 UTF-8，修复 Git Bash 下校验错误信息中文乱码。
- Bash 版阶段内的 Azure CLI 调用失败不再被静默忽略（阶段以 `||` 调用时 `set -e` 失效）：资源组创建、Project 创建等待、Provider 注册、区域列表、配额读取、部署列表读取失败均记为 `Failed` 并返回非零退出码。
- Bash 版阶段 4 读取已有部署失败时不再返回成功，改为记录失败行。
- Bash 版订阅创建失败时，错误信息现在能正确写入结果 CSV；`UserNotAuthorized` 等致命错误会停止阶段（原因：错误文件路径在子 shell 中赋值，父 shell 读取为空）。
- Bash 版订阅创建成功后若回填 CSV 失败，立即停止本阶段并提示手工填写 `SubscriptionId`，避免重跑时重复创建订阅。
- Bash 版交付清单在读取部署列表失败时跳过该项目并报错，不再生成缺少部署信息的清单。
- Bash 版 CSV 校验失败时阶段返回失败并以非零退出码结束，不再继续写入结果文件。

### 新增

- 新增 `tests/smoke.sh` 离线烟雾测试，使用假的 `az`（`tests/fake_az.sh`）覆盖参数校验、阶段 1/2/4 的失败路径，不访问 Azure。

### 文档

- README 按新风格重写，补充测试说明、本项目的来源（clone 自 JungleWolf666/AzureFoundryAIAutomation）与 MIT 许可证。
- 新增 `LICENSE`（MIT）。
- `.gitignore` 忽略 `*.local.csv`，方便把真实配置放在本地副本中。

## [1.0.5] - 2026-09-28

### 新增

- 新增第 6 阶段 `QueryQuotaTier`，按 CSV 中明确填写的 `SubscriptionId` 查询订阅级 Azure OpenAI Quota Tier。
- PowerShell 与 Bash 版本均通过 ARM 控制面预览 API `2025-10-01-preview` 查询并导出 `QuotaTier`、`AssignmentDate`、`TierUpgradePolicy`、状态和错误信息。
- 单个订阅查询失败不会中断其他订阅；不可见、跨租户、未启用或格式错误的订阅会跳过并给出明确提示。

### 调整

- 菜单新增 Quota Tier 查询为第 6 项，原“全流程”后移为第 7 项；README 补充独立运行命令、输出文件和预览 API 注意事项。

## [1.0.4] - 2026-09-21

### 新增

- 新增第 5 阶段 `ExportCredentials`，可独立补导出 Endpoint/API Key，或按 CSV 中明确列出的订阅盘点所有 Foundry 账户和项目。
- 模式 2 支持没有 Foundry Project 的旧版账户，改为账户级导出，并严格限制在 CSV 指定的订阅范围内。
- PowerShell 与 Bash 版本功能对齐，菜单全流程调整为第 6 项；新增 `-SkipLogin`/`--skip-login` 用于复用已登录的 Azure CLI 会话。
- 新增 `-BrowserLogin`/`--browser-login` 登录说明：默认登录方式仍为设备代码流；遇到租户阻止设备代码流时，可改用浏览器登录，且每次运行都需要携带该参数。

### 修复与改进

- 模式 2 改用 ARM REST 读取项目列表，避免依赖较新 Azure CLI 版本；Bash 版本修复 macOS Bash 3.2 下的变量边界和 JSONL 解析问题。
- 空项目名不再生成残缺的 `ProjectEndpoint`；配额和交付清单继续保持 TPM/RPM 格式一致。

### 文档

- README 补充 `53003 BlockedByConditionalAccess` 登录排查，并明确说明默认设备代码登录与 `-BrowserLogin`/`--browser-login` 浏览器登录的选择方式。

## [1.0.3] - 2026-09-18

### 修复与改进

- `FoundryResourceName` 校验放宽为允许大小写字母、数字、连字符（原先仅允许小写），下划线等其他字符仍不允许。
- Azure 账户资源名保留 CSV 中的原始大小写；写入 `customSubDomainName`（自定义子域名，构成访问域名的一部分）时统一转换为小写，符合 Azure 对该字段的 DNS 命名要求。
- 修正前，若 CSV 中填写了大写字母（如 `AzureOpenAI-01`），脚本会直接拒绝该行，需要用户手工改成全小写；现在无需修改 CSV，脚本自动处理域名大小写转换。
- 交付清单 `DeployedModels` 列的容量单位由 `K`（千 TPM）改为 `M`（百万 TPM），自动去除多余小数位（如 `10000K` → `10M`，`3333K` → `3.333M`）。
- `DeployedModels` 中部署名与模型名相同时不再重复显示模型名，仅保留 `部署名(SKU, 容量)`；两者不同（自定义部署名）时才显示 `部署名(模型名, SKU, 容量)`。
- 配额显示新增模型类型识别：当前 Azure 模型配额只有 TPM（文本类）和 RPM（按请求计费）两种。`gpt-image-*`、`dall-e`、`sora` 等模型基于名称关键字识别为 RPM，直接显示为 `<数值> RPM`（不再套用 K/M 千进制换算），方便下游导入 AI 网关时直接按统一枚举值解析，无需再清洗数据。
- 文本类模型（GlobalStandard/DataZoneStandard 等）的配额显示统一补充 `TPM` 后缀（如 `10 K TPM`、`3.333 M TPM`），减少歧义。
- 该识别基于模型名称关键字匹配，属于启发式规则；如遇到未覆盖的新模型类型，仍建议以 Azure 门户实际显示为准。
- 交付清单 `DeployedModels` 列的容量格式统一复用同一套识别逻辑，与阶段 3/4 的控制台日志保持一致。

### 文档

- README 补充"手动删除资源引发软删除冲突"的完整排查/解决步骤：包括资源组级联删除、账户级联删除，以及账户下唯一（默认）项目被删除可能连账户一起删除的情况；给出 `FlagMustBeSetForRestore` 的诊断、purge、重跑阶段顺序，以及避免误删的操作建议（改用 CLI 精确删除项目）。
- 更新 README 顶部版本号与本次版本保持一致。
- README 顶部阶段总览表补充说明：`DeployModels` 阶段执行完成后会自动生成含三个 Endpoint 与可选 API Key 的交付清单，并链接到详细章节。
- 精简"安全设计"章节，移除 `.gitignore` 具体配置细节的描述。

## [1.0.2] - 2026-09-18

### 新增

- 阶段 3 正式执行完成后自动生成交付清单，输出到 `delivery_reports/`。
- 交付清单按项目输出，每个项目一行，包含订阅、项目、区域、部署数量和全部已部署模型。
- 同时输出三个 Endpoint：`OpenAIEndpoint`、`ProjectEndpoint`、`ServicesEndpoint`。
- 交付清单结束前通过交互询问是否包含 API Key，默认不包含。
- 包含 API Key 的文件名带 `_WITH_KEY` 后缀，Bash 版自动将权限设为 `600`。
- 清单数据取自 Azure 实时状态，已存在的历史部署也会一并列出。

### 修复与改进

- 缺少 `Microsoft.CognitiveServices/accounts/listKeys/action` 权限时，`ApiKey` 列留空并继续执行，不中断流程。
- 预演模式不再生成交付清单，避免产生内容不准确的交付文件。
- `.gitignore` 增加 `delivery_reports/` 和 `script_backups/`，避免凭据和备份进入仓库。
- 调整 README 中关于公开仓库的措辞，改为通用的凭据保护提示，避免使用方误解。

## [1.0.1] - 2026-09-16

### 修复

- 将 CSV 回填前的备份统一保存到 CSV 所在目录的 `csv_backups/`，文件名包含原 CSV 名称和时间戳，避免与脚本备份混淆。
- PowerShell 和 Bash 两个版本的 CSV 备份行为保持一致。
- 增加根目录和 Delivery 目录的 `.gitignore`，避免 `csv_backups/`、`logs/`、`results/` 和 `.bak.*` 文件进入公开仓库。
- 版本查询命令现在返回 `v1.0.1`。

## [1.0.0] - 2026-09-16

### 新增

- 合并订阅创建、Foundry 资源创建、模型部署和配额扩容四个阶段。
- 支持 PowerShell 和 Bash 两种运行方式。
- 支持交互式菜单、独立阶段运行和全流程运行。
- 支持按剩余共享配额批量部署模型。
- 支持将已有部署扩容至可用配额上限。
- 支持同一账户内同一模型使用多个 SKU，并通过自定义部署名区分。
- 支持 `--version` / `-Version` 查询脚本版本。

### 修复与改进

- 修复 PowerShell 回写 CSV 时全字段加引号导致后续阶段无法读取的问题。
- 增加 CSV 表头的 BOM 和引号兼容处理。
- 增加订阅创建 429 限流自动重试和 `Retry-After` 退避。
- 根据待创建订阅数量自动选择创建间隔：10 秒、20 秒或 30 秒。
- 支持通过参数覆盖订阅创建间隔。
- 增加 EA/CSP 使用范围提示。
- 完成交付模板脱敏。

## 版本规则

使用语义化版本号：

- `MAJOR`：不兼容的配置或行为变更。
- `MINOR`：向后兼容的新功能。
- `PATCH`：向后兼容的问题修复或文档修正。

Git 标签格式：`vMAJOR.MINOR.PATCH`，例如 `v1.0.0`。
