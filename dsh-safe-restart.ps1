# 重启保护 · DSH Safe Restart
# Copyright (C) 2026 TNT460
#
# 本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证
# （第 3 版或你选择的任何更新版本）的条款重新分发和/或修改它。
#
# 本程序基于「有用」的期望分发，但不提供任何担保；甚至不包含适销性或
# 特定用途适用性的默示担保。详见 GNU 通用公共许可证。
#
# 你应当已随本程序收到一份 GNU 通用公共许可证；如果没有，
# 见 <https://www.gnu.org/licenses/>。

<#
.SYNOPSIS
    DSH Safe Restart —— 带预检、快照、健康检查与自动回滚的 DeepSeek Harness 重启器。

.DESCRIPTION
    为什么需要它：
      DSH 桌面版的插件配置放在 profile 的 package.json / cordis.patch.yml 里。
      一旦某个插件的入口文件坏了、或者版本不兼容，重启后 web boot 会失败，
      DSH 随后会把配置**自动降级**（bundles 砍到 2 项、cordis.patch.yml 被改写成最小版本），
      你之前装的几十个插件配置就此清空，而且不报错、没有提示。

    这个脚本在重启前做三件事来避免上述灾难：
      1. 预检（dry-run）：逐个检查 profile 里声明的 bundle 能否被 import，坏的直接拦下，不重启。
      2. 快照：把 package.json / cordis.patch.yml / cordis.yml 复制一份带时间戳的备份。
      3. 健康检查 + 回滚：重启后如果发现新的 crash 日志或者进程起不来，
         自动把快照还原并再启动一次。

    退出码：
      0  重启成功，DSH 正常
      2  第一次没起来，已自动回滚并恢复
      3  预检拦下（有 bundle 无法 import），什么都没动
      4  回滚后仍然起不来，需要人工介入

.PARAMETER WaitSec
    重启后等待健康的最大秒数，默认 60。

.PARAMETER ProfileName
    要操作的 profile 名（.dsh\profiles 下的目录名）。默认自动选 desktop，没有则选最近修改的。

.PARAMETER SnapRoot
    快照保存目录。默认 %LOCALAPPDATA%\dsh-safe-restart\snapshots。

.PARAMETER SkipSimulate
    跳过预检（不推荐）。

.PARAMETER DryRun
    只做预检和快照，不重启。

.EXAMPLE
    pwsh -File dsh-safe-restart.ps1
    pwsh -File dsh-safe-restart.ps1 -DryRun
    pwsh -File dsh-safe-restart.ps1 -ProfileName work -WaitSec 90
#>
param(
    [int]$WaitSec = 60,
    [string]$ProfileName = '',
    [string]$SnapRoot = '',
    [switch]$SkipSimulate,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- 路径探测
function Find-DshExe {
    # 1) 运行中的进程
    $p = Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p -and $p.Path -and (Test-Path $p.Path)) { return $p.Path }

    # 2) 卸载注册表
    $found = $null
    foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $item = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($item.DisplayName -like '*DeepSeek Harness*' -and $item.InstallLocation) {
                $cand = Join-Path $item.InstallLocation 'DeepSeek Harness.exe'
                if (Test-Path $cand) { $found = $cand }
            }
        }
    }
    if ($found) { return $found }

    # 3) 常见安装位置
    foreach ($cand in @(
        "$env:LOCALAPPDATA\Programs\DeepSeek Harness\DeepSeek Harness.exe",
        "$env:ProgramFiles\DeepSeek Harness\DeepSeek Harness.exe",
        "${env:ProgramFiles(x86)}\DeepSeek Harness\DeepSeek Harness.exe"
    )) {
        if ($cand -and (Test-Path $cand)) { return $cand }
    }
    return $null
}

function Find-ProfileDir {
    $root = Join-Path $env:USERPROFILE '.dsh\profiles'
    if (-not (Test-Path $root)) { return $null }
    if ($ProfileName -ne '') {
        $p = Join-Path $root $ProfileName
        if (Test-Path $p) { return $p }
        return $null
    }
    $preferred = Join-Path $root 'desktop'
    if (Test-Path $preferred) { return $preferred }
    $latest = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { return $latest.FullName }
    return $null
}

function Find-Node {
    $base = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes'
    if (Test-Path $base) {
        foreach ($dir in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)) {
            $cand = Join-Path $dir.FullName 'dependencies\node\bin\node.exe'
            if (Test-Path $cand) { return $cand }
        }
    }
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-Simulate {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $cand = Join-Path $here 'dsh-simulate.mjs'
    if (Test-Path $cand) { return $cand }
    return $null
}

$scriptRoot  = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$stateRoot   = if ($SnapRoot -ne '') { $SnapRoot } else { Join-Path $env:LOCALAPPDATA 'dsh-safe-restart\snapshots' }
$logFile     = Join-Path (Split-Path -Parent $stateRoot) 'safe-restart.log'
$logDir      = Join-Path $env:APPDATA '@deepseek-ai\dsh-desktop\logs'

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logFile) | Out-Null

function Log($msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Output $line
    try { Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 } catch {}
}

Log '==== dsh-safe-restart ===='

$exe = Find-DshExe
if (-not $exe) {
    Log 'ERROR: 找不到 DeepSeek Harness.exe（进程、注册表、常见路径都没命中）'
    Log '       请用 -DshExe 指定，或先手动启动一次 DSH 让进程可被探测'
    exit 3
}
$exeDir = Split-Path -Parent $exe
Log ("exe        : " + $exe)

$profileDir = Find-ProfileDir
if (-not $profileDir) {
    Log 'ERROR: 找不到 profile 目录（%USERPROFILE%\.dsh\profiles 下没有可用 profile）'
    exit 3
}
Log ("profile    : " + $profileDir)

$node = Find-Node
$nodeText = if ($node) { $node } else { '(未找到，预检将跳过)' }
Log ("node       : " + $nodeText)

$simulate = Find-Simulate
$simulateText = if ($simulate) { $simulate } else { '(未找到)' }
Log ("simulate   : " + $simulateText)
Log ("snapshots  : " + $stateRoot)
Log ("log        : " + $logFile)

# ---------------------------------------------------------------- 工具函数
function Snapshot-Dir($stamp) {
    $d = Join-Path $stateRoot $stamp
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    foreach ($f in @('package.json', 'cordis.patch.yml', 'cordis.yml')) {
        $src = Join-Path $profileDir $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $d $f) -Force }
    }
    return $d
}

function Restore-Snapshot($dir) {
    foreach ($f in @('package.json', 'cordis.patch.yml', 'cordis.yml')) {
        $src = Join-Path $dir $f
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $profileDir $f) -Force
            Log ("restored " + $f)
        }
    }
}

function Dsh-Processes {
    return @(Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue)
}

function Crash-Logs {
    if (-not (Test-Path $logDir)) { return @() }
    return @(Get-ChildItem $logDir -Filter 'crash-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
}

function Get-DshListeningPorts($procIds) {
    if (-not $procIds -or $procIds.Count -eq 0) { return @() }
    return @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
             Where-Object { $procIds -contains $_.OwningProcess } |
             Select-Object -ExpandProperty LocalPort)
}

function Wait-Healthy($before, $waitSec) {
    $deadline = (Get-Date).AddSeconds($waitSec)
    $lastCount = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $procs = Dsh-Processes
        $count = $procs.Count
        if ($count -ne $lastCount) { Log ("processes=" + $count); $lastCount = $count }
        if ($count -lt 2) { continue }

        $now = Crash-Logs
        $new = @($now | Where-Object { $before -notcontains $_ })
        if ($new.Count -gt 0) {
            Log ("new crash log: " + ($new -join ', '))
            return @{ ok = $false; reason = 'crash-log'; detail = ($new -join ', ') }
        }

        $ports = Get-DshListeningPorts ($procs | Select-Object -ExpandProperty Id)
        if ($ports.Count -gt 0) {
            return @{ ok = $true; reason = 'ready'; detail = ('ports=' + (($ports | Select-Object -First 3) -join ',')) }
        }
    }
    return @{ ok = $false; reason = 'timeout'; detail = ("no listening port within ${waitSec}s") }
}

function Start-Dsh {
    Start-Process -FilePath $exe -WorkingDirectory $exeDir | Out-Null
}

# ---------------------------------------------------------------- 1. 预检
if (-not $SkipSimulate) {
    if ($simulate -and $node) {
        Log 'dry-run: 检查 bundle 入口能否被 import'
        $out = & $node $simulate 2>&1 | Out-String
        $out.Trim().Split("`n") | ForEach-Object { Log ('  ' + $_.TrimEnd()) }
        if ($LASTEXITCODE -eq 2) {
            Log 'ABORT: 预检发现无法 import 的 bundle，什么都没有改动'
            exit 3
        }
    } else {
        Log 'WARN: 缺少 node 或 dsh-simulate.mjs，跳过预检'
    }
} else {
    Log 'dry-run: 已按参数跳过'
}

# ---------------------------------------------------------------- 2. 快照
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snap = Snapshot-Dir $stamp
Log ("snapshot: " + $snap)

$before = Crash-Logs
Log ("crash logs before: " + $before.Count)

if ($DryRun) {
    $bundles = @()
    try {
        $pkg = Get-Content (Join-Path $profileDir 'package.json') -Raw | ConvertFrom-Json
        $bundles = @($pkg.dsh.profile.bundles)
    } catch {}
    Log ('DRY RUN: 快照已生成，未重启')
    Log ('  bundles: ' + $bundles.Count)
    Log ('  crash logs present: ' + $before.Count)
    exit 0
}

# ---------------------------------------------------------------- 3. 重启
$procs = Dsh-Processes
Log ("killing " + $procs.Count + " processes")
$procs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

Start-Dsh
Log 'started'

$health = Wait-Healthy $before $WaitSec
Log ("health: ok=" + $health.ok + " reason=" + $health.reason + " " + $health.detail)

if ($health.ok) {
    Log 'OK: DSH 已起来'
    exit 0
}

# ---------------------------------------------------------------- 4. 回滚
Log 'ROLLBACK: 还原快照并重启'
Restore-Snapshot $snap
Dsh-Processes | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Start-Dsh
$health2 = Wait-Healthy $before 40
Log ("post-rollback health: ok=" + $health2.ok + " reason=" + $health2.reason)

if ($health2.ok) { exit 2 }
Log 'CRITICAL: 回滚后仍不健康，需要人工排查'
exit 4
