<#
.SYNOPSIS
    按订阅列表批量生成 Azure_Foundry_AI_Plan 格式的 CSV：每个订阅一行，名称按序号生成，地区按订阅顺序轮询。

.DESCRIPTION
    只生成本地配置文件，不调用 Azure，不创建任何资源。
    - ResourceGroupName、FoundryResourceName、DefaultProjectName 按“前缀 + 序号”生成，序号从 -StartIndex 开始。
    - Location 按订阅顺序轮询：第 N 个订阅使用 Location[N % Location.Count]。
    - 生成后请检查输出文件，再用 -Stage CreateFoundry -DryRun 预演。

.EXAMPLE
    .\tools\New-PlanCsv.ps1 -SubscriptionName "sub-a","sub-b","sub-c" -SubscriptionId "<guid-a>","<guid-b>","<guid-c>" `
        -NamePrefix "contoso" -Location "eastus2","swedencentral" `
        -ModelNames "gpt-4o;gpt-4o-mini" -ModelVersion "2026-01-01" -OutputPath .\contoso.local.csv

.EXAMPLE
    .\tools\New-PlanCsv.ps1 -SubscriptionName "sub-a","sub-b" -NamePrefix "contoso" -StartIndex 41 `
        -Location "eastus2" -ModelNames "gpt-4o-mini" -ModelVersion "2026-01-01" -OutputPath .\batch2.local.csv
#>

[CmdletBinding()]
param(
    # 订阅名称，每个订阅生成一行。使用已有订阅时必须与 Azure 中的名称完全一致。
    [Parameter(Mandatory = $true)]
    [string[]]$SubscriptionName,

    # 与 SubscriptionName 一一对应的订阅 ID。新建订阅（阶段 1）时可留空。
    [string[]]$SubscriptionId = @(),

    # 仅阶段 1（EA 新建订阅）需要；已有订阅时留空即可。
    [string]$BillingAccountName = '',
    [string]$EnrollmentAccountName = '',

    # 资源名前缀，最终为 <NamePrefix>-<序号>。必须在 Azure 全局范围内唯一，不要使用通用名。
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,40}$')]
    [string]$NamePrefix,

    # 起始序号。同一前缀续跑时，用上一批最大序号 + 1。
    [int]$StartIndex = 1,

    # 候选区域，按订阅顺序轮询。
    [Parameter(Mandatory = $true)]
    [string[]]$Location,

    # 资源组前缀，留空时为 <NamePrefix>-rg。
    [string]$ResourceGroupPrefix = '',

    # Project 前缀，最终为 <ProjectPrefix>-<序号>。
    [string]$ProjectPrefix = 'proj',

    # 与主脚本 ModelNames 写法相同，分号分隔，例如 "gpt-4o;gpt-4o-mini"。
    [Parameter(Mandatory = $true)]
    [string]$ModelNames,

    [string]$ModelVersion = '',
    [string]$ModelFormat = 'OpenAI',
    [string]$DeploymentType = 'GlobalStandard',

    # 留空表示用满剩余配额。
    [string]$DeploymentCapacityK = '',

    [string]$OutputPath = (Join-Path (Get-Location) 'Azure_Foundry_AI_Plan.local.csv'),

    # 允许覆盖已存在的输出文件。
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# pwsh -File 下 "a","b" 会被当成一个字符串，因此统一支持逗号分隔写法（两种写法都可用）。
# SubscriptionId 允许留空，需保留空位以与 SubscriptionName 对齐。
function ConvertTo-List {
    param([string[]]$Values, [switch]$KeepEmpty)
    $items = @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() })
    if ($KeepEmpty) {
        if (@($items | Where-Object { $_ }).Count -eq 0) { return @() }
        return $items
    }
    return @($items | Where-Object { $_ })
}
$SubscriptionName = ConvertTo-List -Values $SubscriptionName
$SubscriptionId = ConvertTo-List -Values $SubscriptionId -KeepEmpty
$Location = ConvertTo-List -Values $Location
if ($SubscriptionName.Count -eq 0) { throw '-SubscriptionName 不能为空。' }
if ($Location.Count -eq 0) { throw '-Location 不能为空。' }

$header = 'BillingAccountName,EnrollmentAccountName,SubscriptionName,SubscriptionId,ResourceGroupName,FoundryResourceName,DefaultProjectName,Location,ModelNames,ModelVersion,ModelFormat,DeploymentType,DeploymentCapacityK'
$foundryPattern = '^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}[a-zA-Z0-9]$'
$guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

if ($SubscriptionId.Count -gt 0 -and $SubscriptionId.Count -ne $SubscriptionName.Count) {
    throw "SubscriptionId 数量（$($SubscriptionId.Count)）必须与 SubscriptionName 数量（$($SubscriptionName.Count)）一致，或留空。"
}
if (Test-Path -LiteralPath $OutputPath) {
    if (-not $Force) { throw "输出文件已存在：$OutputPath。确认覆盖请加 -Force，或换一个 -OutputPath。" }
}

$resourceGroupBase = if ($ResourceGroupPrefix) { $ResourceGroupPrefix } else { "$NamePrefix-rg" }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add($header)
$summary = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $SubscriptionName.Count; $i++) {
    $name = $SubscriptionName[$i].Trim()
    $id = if ($SubscriptionId.Count -gt 0) { $SubscriptionId[$i].Trim() } else { '' }
    if ($name -match '[,|]') { throw "SubscriptionName「$name」不能包含逗号或竖线。" }
    if ($id -and $id -notmatch $guidPattern) { throw "SubscriptionId「$id」不是合法 GUID。" }

    $sequence = '{0:D3}' -f ($StartIndex + $i)
    $resourceGroup = "$resourceGroupBase-$sequence"
    $foundry = "$NamePrefix-$sequence"
    $project = "$ProjectPrefix-$sequence"
    $region = $Location[$i % $Location.Count].Trim().ToLowerInvariant()

    if ($foundry -notmatch $foundryPattern) { throw "FoundryResourceName「$foundry」不合法（2-64 位字母、数字、连字符，首尾为字母或数字）。" }
    if ($foundry.Length -gt 64) { throw "FoundryResourceName「$foundry」超过 64 位。请缩短 -NamePrefix。" }
    if ($project.Length -gt 64) { throw "DefaultProjectName「$project」超过 64 位。请缩短 -ProjectPrefix。" }

    $lines.Add(@(
            $BillingAccountName, $EnrollmentAccountName, $name, $id, $resourceGroup, $foundry, $project,
            $region, $ModelNames, $ModelVersion, $ModelFormat, $DeploymentType, $DeploymentCapacityK
        ) -join ','
    )
    $summary.Add([pscustomobject]@{ Subscription = $name; ResourceGroup = $resourceGroup; Foundry = $foundry; Project = $project; Location = $region })
}

Set-Content -LiteralPath $OutputPath -Value $lines.ToArray() -Encoding UTF8
Write-Host "已生成 $($summary.Count) 行：$OutputPath" -ForegroundColor Green
$summary | Format-Table -AutoSize | Out-String | Write-Host
Write-Host '下一步：用 -Stage CreateFoundry -DryRun 预演，确认无误后再正式执行。' -ForegroundColor Cyan
