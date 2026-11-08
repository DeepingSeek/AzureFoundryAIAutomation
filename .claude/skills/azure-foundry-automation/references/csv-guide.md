# CSV 配置指南

配置文件是 `Azure_Foundry_AI_Plan.csv` 的副本（建议命名为 `*.local.csv`，已被 `.gitignore` 忽略）。列名与顺序必须完全一致：

```csv
BillingAccountName,EnrollmentAccountName,SubscriptionName,SubscriptionId,ResourceGroupName,FoundryResourceName,DefaultProjectName,Location,ModelNames,ModelVersion,ModelFormat,DeploymentType,DeploymentCapacityK
```

## 字段

| 字段 | 必填阶段 | 说明 |
|---|---|---|
| `BillingAccountName` | 阶段 1 | EA Billing Account **ID**（不是完整资源 ID，不以 `/providers/` 开头）。已有订阅可留空。 |
| `EnrollmentAccountName` | 阶段 1 | EA Enrollment Account **ID**。已有订阅可留空。 |
| `SubscriptionName` | 阶段 1–4 | 订阅名称。使用已有订阅时必须与 Azure 门户中的名称完全一致，否则脚本拒绝执行。 |
| `SubscriptionId` | 阶段 2–6 | 订阅 GUID。阶段 1 成功后自动回填；已有订阅需手工填写。 |
| `ResourceGroupName` | 阶段 2–5 | 资源组名称，不存在时创建。 |
| `FoundryResourceName` | 阶段 2–5 | Foundry 账户名。2–64 位字母、数字、连字符，首尾为字母或数字，**不支持下划线**，全局唯一。同时用于自定义子域名（写入时统一转小写）。 |
| `DefaultProjectName` | 阶段 2–5 | 默认 Project 名称。 |
| `Location` | 阶段 2–4 | 区域，如 `eastus2`、`swedencentral`。 |
| `ModelNames` | 阶段 3–4 | 分号分隔的模型列表，见下文。 |
| `ModelVersion` | 阶段 3–4 | 默认模型版本，格式 `YYYY-MM-DD`。以门户中该区域可用的版本为准。 |
| `ModelFormat` | 阶段 3–4 | 默认格式，留空按 `OpenAI`。 |
| `DeploymentType` | 阶段 3–4 | 默认 SKU，留空按 `GlobalStandard`。常见值：`GlobalStandard`、`DataZoneStandard`。 |
| `DeploymentCapacityK` | 阶段 3 | 留空表示用满剩余配额；填正整数表示固定容量（K TPM），超过剩余配额时自动降到剩余配额。 |

## ModelNames 写法

省略的部分回退到该行的 `ModelVersion` / `ModelFormat` / `DeploymentType`：

```text
gpt-4o                                         仅模型名
gpt-4o:2026-01-01                              模型名 + 版本
gpt-4o::Fireworks                              模型名 + 格式
gpt-4o:::DataZoneStandard                      模型名 + SKU
gpt-4o:2026-01-01:OpenAI:DataZoneStandard      模型名 + 版本 + 格式 + SKU
gpt-4o-dz=gpt-4o:::DataZoneStandard            自定义部署名 = 模型名 + SKU
```

## 常见场景

**同一模型，两种 SKU。** 同一账户内部署名必须唯一，第二个 SKU 使用不同部署名：

```csv
,,SUBSCRIPTION-DEMO,<guid>,rg-foundry-demo,demo-foundry-01-eus2-001,proj-demo-eus2,eastus2,gpt-4o;gpt-4o-mini,2026-01-01,OpenAI,GlobalStandard,
,,SUBSCRIPTION-DEMO,<guid>,rg-foundry-demo,demo-foundry-01-eus2-001,proj-demo-eus2,eastus2,gpt-4o-dz=gpt-4o:::DataZoneStandard,2026-01-01,OpenAI,DataZoneStandard,
```

**同一订阅下多个账户。** 保持 `SubscriptionName` 和 `SubscriptionId` 相同，分别指定不同的 `FoundryResourceName` 和 `DefaultProjectName`。注意：同一订阅、同一区域内，多个账户共享同一模型的配额池。脚本会在同一次运行中扣减已分配额度，后面的行会看到更少的剩余额度（可能显示 `NoQuota`）。

**部署名必须与模型名完全一致。** 只能使用两个不同的 Foundry 账户，每个账户内使用裸模型名。

## 命名建议

```text
FoundryResourceName   <客户简称>-foundry-<负载>-<区域>-<序号>     例：demo-foundry-01-eus2-001
DefaultProjectName    proj-<负载>-<环境>-<区域>                   例：proj-demo-prod-eus2
```

`FoundryResourceName` 必须全局唯一。不要使用 `foundry-ai-01` 这类通用名。
