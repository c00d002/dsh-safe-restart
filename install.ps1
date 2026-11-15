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
    在桌面创建「重启 DSH（安全）」快捷方式。

.DESCRIPTION
    双击本脚本即可安装。快捷方式指向同目录的 dsh-safe-restart-ui.ps1，
    用 pwsh（PowerShell 7）执行；没有 pwsh 时退回 Windows PowerShell 5.1。

.PARAMETER Uninstall
    删除已经创建的快捷方式，而不是创建它。

.EXAMPLE
    pwsh -File install.ps1
    pwsh -File install.ps1 -Uninstall
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$uiScript = Join-Path $here 'dsh-safe-restart-ui.ps1'
$desktop = [Environment]::GetFolderPath('Desktop')
$linkName = '重启DSH（安全）.lnk'
$linkPath = Join-Path $desktop $linkName

if ($Uninstall) {
    if (Test-Path $linkPath) {
        Remove-Item $linkPath -Force
        Write-Host "已删除快捷方式：$linkPath" -ForegroundColor Yellow
    } else {
        Write-Host "没有找到快捷方式：$linkPath" -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path $uiScript)) {
    Write-Host "找不到 dsh-safe-restart-ui.ps1（应该在 $here）" -ForegroundColor Red
    exit 1
}

$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
$fallback = $false
if (-not $shell) {
    $shell = (Get-Command powershell -ErrorAction SilentlyContinue).Source
    $fallback = $true
}
if (-not $shell) {
    Write-Host '找不到 pwsh 或 powershell' -ForegroundColor Red
    exit 1
}

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($linkPath)
$shortcut.TargetPath = $shell
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$uiScript`""
$shortcut.WorkingDirectory = $here
$shortcut.Description = '带预检、快照和自动回滚的 DeepSeek Harness 重启器'
$shortcut.IconLocation = "$shell,0"
$shortcut.Save()

Write-Host '已创建快捷方式：' -ForegroundColor Green
Write-Host "  $linkPath"
Write-Host ("  目标: {0} -NoProfile -ExecutionPolicy Bypass -File `"{1}`"" -f $shell, $uiScript)
if ($fallback) {
    Write-Host '提示：没检测到 pwsh，快捷方式会用 Windows PowerShell 5.1 运行。' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '双击桌面上的「重启DSH（安全）」即可使用。' -ForegroundColor Green
