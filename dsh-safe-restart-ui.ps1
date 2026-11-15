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
    DSH Safe Restart 的图形入口：弹确认框 → 跑预检/重启 → 按退出码弹结果。

.DESCRIPTION
    双击运行（或做成桌面快捷方式）。主脚本在同目录的 dsh-safe-restart.ps1。

    退出码 → 提示文案：
      0  重启成功
      2  第一次没起来，已自动回滚
      3  预检拦下，什么都没动（配置是安全的）
      4  回滚后仍起不来，需要人工看日志
#>

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$main = Join-Path $here 'dsh-safe-restart.ps1'
$stateDir = Join-Path $env:LOCALAPPDATA 'dsh-safe-restart'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$uiLog = Join-Path $stateDir 'ui.log'
$mainLog = Join-Path $stateDir 'safe-restart.log'

function Note($m) {
    try { Add-Content -LiteralPath $uiLog -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding UTF8 } catch {}
}

$title = '重启 DeepSeek Harness'

if (-not (Test-Path $main)) {
    [System.Windows.Forms.MessageBox]::Show(
        "找不到主脚本：`n$main`n`n请把 dsh-safe-restart.ps1 和本文件放在同一个目录。",
        $title, 'OK', 'Error') | Out-Null
    exit 1
}

$confirm = @"
即将重启 DeepSeek Harness。

流程：
  1. 预检 —— 检查 profile 里每个插件能否被加载
  2. 快照 —— 备份 package.json / cordis.patch.yml / cordis.yml
  3. 重启 —— 关闭并重新启动 DSH
  4. 健康检查 —— 起不来会自动回滚到刚才的备份再启一次

窗口会消失 40-70 秒。会话和对话记录都在磁盘上，不会丢。

现在重启吗？
"@

Note 'confirm shown'
$ans = [System.Windows.Forms.MessageBox]::Show(
    $confirm, $title, 'YesNo', 'Question', 'Button1')
Note ('answer: ' + $ans)

if ($ans -ne 'Yes') { Note 'cancelled'; exit 0 }

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
Note ('shell: ' + $pwsh)
Note 'running main'

$proc = Start-Process -FilePath $pwsh `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $main) `
    -WindowStyle Hidden -PassThru -Wait

$code = $proc.ExitCode
Note ('exit code: ' + $code)

$text = switch ($code) {
    0 { '重启成功，DSH 已经正常起来。' }
    2 { 'DSH 第一次没起来，已自动回滚到重启前的配置并恢复。' }
    3 { "预检发现插件加载失败，已拦下，什么都没有改动。`n`n配置是安全的，你可以先修好那个插件再重启。`n`n日志：$mainLog" }
    4 { "回滚后仍然起不来，需要手动检查。`n`n日志：$mainLog" }
    default { "退出码 $code`n`n日志：$mainLog" }
}

$icon = if ($code -eq 0) { 'Information' } elseif ($code -eq 3) { 'Warning' } else { 'Error' }
[System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', $icon) | Out-Null
Note 'done'
