<#
.SYNOPSIS
    PowerShell 版离线烟雾测试：使用假的 az（tests/fake_az.sh）验证主脚本与批量生成器的关键路径，不访问 Azure。

.DESCRIPTION
    假 az 需要通过 Git Bash 运行，因此本测试需要安装 Git for Windows。
    运行：pwsh -File .\tests\smoke.ps1
    如果 Git Bash 不在默认位置，用 -BashPath 指定，例如：-BashPath "D:\software\Git\bin\bash.exe"

.PARAMETER BashPath
    Git Bash 的 bash.exe 路径。留空时自动查找 Program Files 下的 Git。
#>

[CmdletBinding()]
param(
    [string]$BashPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testsDir = $PSScriptRoot
$repoDir = Split-Path -Parent $testsDir
$mainScript = Join-Path $repoDir 'Azure_Foundry_AI_Automation.ps1'
$generatorScript = Join-Path $repoDir 'tools\New-PlanCsv.ps1'
$fixtures = Join-Path $testsDir 'fixtures'
$fakeAz = Join-Path $testsDir 'fake_az.sh'
$tenant = '00000000-0000-0000-0000-000000000000'

function Find-GitBash {
    $candidates = @(
        $BashPath,
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    if (-not $candidates) {
        throw '未找到 Git Bash（bash.exe）。请用 -BashPath 指定，例如 "C:\Program Files\Git\bin\bash.exe"。'
    }
    @($candidates)[0]
}

# 注意：不要用 WSL 的 bash.exe（位于 System32），它无法识别 Windows 路径下的假 az。
$gitBash = Find-GitBash
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('foundry-ps-smoke-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Path $bin -Force | Out-Null
Set-Content -LiteralPath (Join-Path $bin 'az.cmd') -Value "@echo off`r`n`"$gitBash`" `"$fakeAz`" %*" -Encoding ASCII

$env:PATH = "$bin;$env:PATH"
$env:FAKE_MODELS = Join-Path $fixtures 'models.json'
$env:FAKE_USAGE = Join-Path $fixtures 'usage.json'
$env:FAKE_CS_ACCOUNTS = Join-Path $fixtures 'cs_accounts.json'
$env:FAKE_ACCOUNTS = Join-Path $fixtures 'accounts.json'
Remove-Item Env:FAKE_FAIL -ErrorAction SilentlyContinue

$script:passCount = 0
$script:failCount = 0
function Check {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:passCount++; Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $script:failCount++; Write-Host "  FAIL  $Name" -ForegroundColor Red }
}

# 运行主脚本；$StdinLines 用于回答交互式提示。返回退出码，输出写入 <Out>\stdout.txt。
function Invoke-MainScript {
    param([string]$Out, [string[]]$Arguments, [string[]]$StdinLines = @())
    New-Item -ItemType Directory -Path $Out -Force | Out-Null
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mainScript) + $Arguments + @('-OutputRoot', $Out)
    if ($StdinLines.Count -gt 0) {
        $StdinLines | & pwsh @all *> (Join-Path $Out 'stdout.txt')
    }
    else {
        @() | & pwsh @all *> (Join-Path $Out 'stdout.txt')
    }
    $LASTEXITCODE
}

function Get-ResultRows {
    param([string]$Out, [string]$Prefix)
    $file = Get-ChildItem -LiteralPath (Join-Path $Out 'results') -Filter "$Prefix*.csv" | Select-Object -First 1
    if (-not $file) { return @() }
    @(Import-Csv -LiteralPath $file.FullName)
}

try {
    Write-Host '== 版本与帮助 ==' -ForegroundColor Cyan
    $version = & pwsh -NoProfile -ExecutionPolicy Bypass -File $mainScript -Version 2>&1
    Check '-Version 输出版本' ("$version" -match 'Azure Foundry AI Automation v')

    Write-Host '== 阶段 3：同一配额池的额度记账 ==' -ForegroundColor Cyan
    $quotaOut = Join-Path $work 'quota'
    $rc = Invoke-MainScript -Out $quotaOut -Arguments @('-TenantId', $tenant, '-Stage', 'DeployModels', '-DryRun', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_shared_quota.csv'))
    Check '共享配额的两行预演正常结束' ($rc -eq 0)
    $rows = @(Get-ResultRows -Out $quotaOut -Prefix 'stage3_')
    Check '首个账户按全部剩余额度计划部署（10）' ($rows.Count -ge 1 -and $rows[0].CapacityK -eq '10' -and $rows[0].Status -eq 'WhatIf')
    Check '同一配额池的后续账户剩余额度为 0（NoQuota）' ($rows.Count -ge 2 -and $rows[1].Status -eq 'NoQuota')

    Write-Host '== 阶段 2：区域模型预检 ==' -ForegroundColor Cyan
    $modelOut = Join-Path $work 'model'
    $rc = Invoke-MainScript -Out $modelOut -Arguments @('-TenantId', $tenant, '-Stage', 'CreateFoundry', '-DryRun', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_unsupported_model.csv'))
    Check '区域不支持模型时以 1 退出' ($rc -eq 1)
    $rows = @(Get-ResultRows -Out $modelOut -Prefix 'stage2_')
    Check '区域不支持模型时资源状态为 NotStarted' ($rows.Count -ge 1 -and $rows[0].ResourceGroupStatus -eq 'NotStarted')
    Check '区域不支持模型时说明原因' ($rows.Count -ge 1 -and $rows[0].ErrorMessage -match '不支持以下模型组合')

    Write-Host '== 阶段 5：旧版 OpenAI 资源（可选） ==' -ForegroundColor Cyan
    $legacyOut = Join-Path $work 'legacy'
    $rc = Invoke-MainScript -Out $legacyOut -Arguments @('-TenantId', $tenant, '-Stage', 'ExportCredentials', '-IncludeLegacyOpenAI', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_existing_subscription.csv')) -StdinLines @('2', 'YES', '')
    Check '旧版 OpenAI 全量盘点正常结束' ($rc -eq 0)
    $report = Get-ChildItem -LiteralPath (Join-Path $legacyOut 'delivery_reports') -Filter 'foundry_endpoints_scan_*.csv' -ErrorAction SilentlyContinue | Select-Object -First 1
    Check '开启开关时旧版资源进入清单' ($report -and ((Get-Content -LiteralPath $report.FullName -Raw) -match 'legacy-aoai-01'))

    $defaultOut = Join-Path $work 'legacy-default'
    $null = Invoke-MainScript -Out $defaultOut -Arguments @('-TenantId', $tenant, '-Stage', 'ExportCredentials', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_existing_subscription.csv')) -StdinLines @('2', 'YES', '')
    Check '默认不扫描旧版 OpenAI 资源' (-not ((Get-Content -LiteralPath (Join-Path $defaultOut 'stdout.txt') -Raw) -match 'legacy-aoai-01'))

    Write-Host '== CSP 协议：拒绝阶段 1 与 All ==' -ForegroundColor Cyan
    $cspOut = Join-Path $work 'csp'
    $rc = Invoke-MainScript -Out $cspOut -Arguments @('-TenantId', $tenant, '-Stage', 'CreateSubscription', '-AgreementType', 'CSP', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_new_subscriptions.csv'))
    Check 'CSP 运行阶段 1 时以 1 退出' ($rc -eq 1)
    Check 'CSP 运行阶段 1 时给出拒绝原因' ((Get-Content -LiteralPath (Join-Path $cspOut 'stdout.txt') -Raw) -match 'CSP 客户的订阅由合作伙伴创建')
    $rc = Invoke-MainScript -Out (Join-Path $work 'csp-all') -Arguments @('-TenantId', $tenant, '-Stage', 'All', '-AgreementType', 'CSP', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_new_subscriptions.csv'))
    Check 'CSP 运行 All 时以 1 退出' ($rc -eq 1)

    Write-Host '== 预检（只读） ==' -ForegroundColor Cyan
    $pfOut = Join-Path $work 'preflight-quota'
    $rc = Invoke-MainScript -Out $pfOut -Arguments @('-TenantId', $tenant, '-Stage', 'Preflight', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_shared_quota.csv'))
    Check '预检存在配额 WARN 但无 FAIL 时以 0 退出' ($rc -eq 0)
    $pfRows = @(Get-ResultRows -Out $pfOut -Prefix 'stage0_preflight')
    Check '预检输出包含配额检查结果' (@($pfRows | Where-Object { $_.Check -eq 'Quota' }).Count -eq 2)
    Check '第二个账户的配额检查为 WARN' (@($pfRows | Where-Object { $_.Check -eq 'Quota' -and $_.Status -eq 'WARN' }).Count -eq 1)
    $quotaReq = @(Get-ResultRows -Out $pfOut -Prefix 'quota_request')
    Check '配额不足的行写入 quota_request' ($quotaReq.Count -eq 1 -and $quotaReq[0].ModelName -eq 'gpt-4o-mini')

    $pfModel = Join-Path $work 'preflight-model'
    $rc = Invoke-MainScript -Out $pfModel -Arguments @('-TenantId', $tenant, '-Stage', 'Preflight', '-SkipLogin', '-Csv', (Join-Path $fixtures 'plan_unsupported_model.csv'))
    Check '预检存在模型 FAIL 时以 1 退出' ($rc -eq 1)
    $pfModelRows = @(Get-ResultRows -Out $pfModel -Prefix 'stage0_preflight')
    Check '预检标出不支持的模型组合' (@($pfModelRows | Where-Object { $_.Check -eq 'Model' -and $_.Status -eq 'FAIL' }).Count -eq 1)

    Write-Host '== 阶段 1：回填 CSV 失败时停止（避免重复创建） ==' -ForegroundColor Cyan
    $wbOut = Join-Path $work 'writeback'
    $wbCsv = Join-Path $work 'writeback.local.csv'
    Copy-Item -LiteralPath (Join-Path $fixtures 'plan_new_subscriptions.csv') -Destination $wbCsv
    # 只读文件无法回填，用来模拟回填失败。
    (Get-Item -LiteralPath $wbCsv).IsReadOnly = $true
    $savedAccounts = $env:FAKE_ACCOUNTS
    $env:FAKE_ACCOUNTS = Join-Path $fixtures 'accounts_empty.json'
    $rc = Invoke-MainScript -Out $wbOut -Arguments @('-TenantId', $tenant, '-Stage', 'CreateSubscription', '-SkipLogin', '-CreateDelaySeconds', '0', '-Csv', $wbCsv) -StdinLines @('EA', 'YES')
    $env:FAKE_ACCOUNTS = $savedAccounts
    (Get-Item -LiteralPath $wbCsv).IsReadOnly = $false
    Check '回填失败时以 1 退出' ($rc -eq 1)
    $wbRows = @(Get-ResultRows -Out $wbOut -Prefix 'stage1_')
    Check '回填失败时只记录一行（不继续创建下一个订阅）' ($wbRows.Count -eq 1)
    Check '回填失败行保留新订阅 ID' ($wbRows.Count -eq 1 -and $wbRows[0].SubscriptionId -eq '22222222-2222-2222-2222-222222222222')

    Write-Host '== 批量生成 CSV（tools\New-PlanCsv.ps1） ==' -ForegroundColor Cyan
    $genCsv = Join-Path $work 'batch.local.csv'
    & $generatorScript -SubscriptionName 'sub-a,sub-b,sub-c' -SubscriptionId '11111111-2222-3333-4444-555555555555,11111111-2222-3333-4444-555555555556,11111111-2222-3333-4444-555555555557' `
        -NamePrefix 'contoso' -StartIndex 41 -Location 'eastus2,swedencentral' -ModelNames 'gpt-4o;gpt-4o-mini' -ModelVersion '2026-01-01' -OutputPath $genCsv | Out-Null
    $gen = @(Import-Csv -LiteralPath $genCsv)
    Check '生成 3 行' ($gen.Count -eq 3)
    Check '序号从 StartIndex 开始（contoso-041）' ($gen[0].FoundryResourceName -eq 'contoso-041')
    Check '地区按订阅顺序轮询' (($gen | ForEach-Object { $_.Location }) -join ',' -eq 'eastus2,swedencentral,eastus2')
    $overwriteBlocked = $false
    try { & $generatorScript -SubscriptionName 'sub-a' -NamePrefix 'contoso' -Location 'eastus2' -ModelNames 'gpt-4o' -OutputPath $genCsv | Out-Null }
    catch { $overwriteBlocked = $true }
    Check '输出文件已存在时拒绝覆盖（需 -Force）' $overwriteBlocked
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "通过 $script:passCount 项，失败 $script:failCount 项。"
if ($script:failCount -gt 0) { exit 1 }
exit 0
