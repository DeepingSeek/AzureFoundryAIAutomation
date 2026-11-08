# 排错指南

先看结果 CSV 的 `ErrorMessage` 列和 `logs\` 下的日志，再对照下表。

## 登录

| 现象 | 原因 | 处理 |
|---|---|---|
| `53003 BlockedByConditionalAccess`，提示 "Block device code flow" | 租户阻止设备代码登录（脚本默认方式） | 加 `-BrowserLogin`，**每次运行都要带** |
| 浏览器登录也被拦截 | 条件访问限制了登录方式或设备 | 请客户 Entra 管理员为账号或应用添加例外；或改用服务主体登录，再用 `-SkipLogin` |
| `-SkipLogin` 报"租户不一致" | 当前 Azure CLI 会话属于其他租户 | `az login --tenant <TENANT-ID>` 后重试 |
| 提示未找到 Azure CLI | 未安装或终端未重启 | 安装 Azure CLI，重新打开终端 |

## 订阅与权限

| 现象 | 原因 | 处理 |
|---|---|---|
| `UserNotAuthorized` | 账号无权在该 Billing/Enrollment Account 下创建订阅 | 请 Account Owner 确认权限 |
| 订阅名不匹配 | CSV 的 `SubscriptionName` 与 Azure 实际名称不同 | 改为门户中显示的名称 |
| 订阅"不可见"或"已跳过" | 当前登录账号看不到该订阅，或订阅未启用，或属于其他租户 | 确认登录的是正确租户，订阅状态为 Enabled |
| 阶段 1 回填 CSV 失败 | 订阅已创建但 CSV 未更新 | 脚本已停止本阶段。把日志中的 `SubscriptionId` 手工填入 CSV，**不要重跑阶段 1**，否则会重复创建 |
| 限流 429 | 租户级订阅创建限流 | 脚本会自动退避重试；数量多时分批执行，或加 `-CreateDelaySeconds 30` |

## Foundry 账户与项目

| 现象 | 原因 | 处理 |
|---|---|---|
| `CustomDomainInUse` | `FoundryResourceName` 已被全局占用 | 换一个更唯一的名称 |
| `NotStarted` 且提示"区域不支持以下模型组合" | 该区域没有 CSV 中的模型、版本或 SKU | 换区域，或换模型版本/SKU；预检在创建任何资源前完成，不会留下半成品 |
| `FlagMustBeSetForRestore` | 同名账户或项目处于软删除保护期 | 见下文"软删除" |
| 资源组位于其他区域 / 账户类型或区域不一致（`Conflict` 或 `Failed`，`ErrorMessage` 说明不一致） | 已有资源与计划冲突 | 不要覆盖。换名称，或确认后由用户自行处理已有资源 |

### 软删除（`FlagMustBeSetForRestore`）

常见诱因：门户删除了资源组（级联删除账户），或在账户只剩默认项目时删除了项目。

```powershell
az account set --subscription <订阅ID>
az cognitiveservices account list-deleted --output table
# 确认不需要恢复后，才执行（不可逆）：
az cognitiveservices account purge --location <区域> --resource-group <资源组> --name <账户名>
```

`purge` 返回成功不代表立即生效，可能需要等待数分钟到数十分钟。`list-deleted` 为空后，重新运行阶段 2，再运行阶段 3（账户被删除后部署也会丢失）。

## 模型与配额

| 现象 | 原因 | 处理 |
|---|---|---|
| `NoQuota` | 剩余配额为 0；或同一配额池内先前的行已用完 | 申请配额，或减少其他行的容量 |
| `Failed`，"没有 … 的配额项" | 该区域没有此 SKU + 模型组合的配额 | 换区域或 SKU |
| `Failed`，"读取区域 … 的配额失败" / "模型列表失败" | 读取 Azure 数据失败（网络、权限、登录） | 检查 `az account show` 与权限，重试 |
| 扩容（阶段 4）后容量未变化 | 当前区域无剩余共享配额 | 正常现象，查看结果中的 `Skipped` 与 `IncreaseK` |

## 导出与交付

| 现象 | 原因 | 处理 |
|---|---|---|
| 阶段 5 不生成文件 | 预演模式不支持阶段 5，或没有找到 Foundry 账户 | 去掉 `-DryRun`；确认订阅内确有 AIServices 账户（或加 `-IncludeLegacyOpenAI`） |
| 交付清单中 `ApiKey` 为空 | 未输入 `KEY`，或账号无 `listKeys` 权限 | 需要时重新运行阶段 5，并输入 `KEY` |
| 清单缺少某个项目 | 读取该账户的部署列表失败，脚本已跳过并报错 | 查看日志中的该账户错误，修复后重跑阶段 5 |

## 排查时的通用步骤

1. 打开 `results\` 下最新的 CSV，找到 `Failed` / `NotStarted` 行。
2. 读取 `ErrorMessage`，对照上表。
3. 查看 `logs\` 中同一时间戳的日志，获得完整上下文。
4. 修复后，先预演，再正式执行。
