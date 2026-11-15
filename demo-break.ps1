param([switch]$KeepBroken)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$profileDir = 'D:\DSH\data\profiles\desktop'
$pkg        = Join-Path $profileDir 'package.json'
$pluginDir  = Join-Path $profileDir 'node_modules\demo-broken-plugin'
$name       = 'demo-broken-plugin'

Write-Host ''
Write-Host '  搭一个"真会炸"的演示环境' -ForegroundColor Cyan
Write-Host ''

# ---- 1. 写坏插件 ----
New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null

$pkgJson = @'
{
  "name": "demo-broken-plugin",
  "version": "0.0.1",
  "type": "module",
  "main": "index.js"
}
'@
[IO.File]::WriteAllText((Join-Path $pluginDir 'package.json'), $pkgJson, (New-Object Text.UTF8Encoding $false))

$indexJs = @'
// 这个依赖不存在 —— import 时必炸
import { nothing } from 'this-package-does-not-exist-xyz';

export function apply() {
  return nothing;
}
'@
[IO.File]::WriteAllText((Join-Path $pluginDir 'index.js'), $indexJs, (New-Object Text.UTF8Encoding $false))

Write-Host ("  插件已写入  {0}" -f $pluginDir) -ForegroundColor DarkGray

# ---- 2. 加进 bundles ----
$raw = [IO.File]::ReadAllText($pkg, [Text.Encoding]::UTF8)
$j = $raw | ConvertFrom-Json
$bundles = @($j.dsh.profile.bundles | Where-Object { $_ -ne $name })
$before = $bundles.Count
$j.dsh.profile.bundles = @($bundles + $name)
[IO.File]::WriteAllText($pkg, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))

Write-Host ("  bundles     {0} -> {1}" -f $before, $j.dsh.profile.bundles.Count) -ForegroundColor DarkGray
Write-Host ''

# ---- 3. 验证它确实会炸 ----
Write-Host '  验证（dry-run 应该 exit 3）' -ForegroundColor Yellow
Write-Host ''
$script = 'D:\dpsk\projects\dsh-safe-restart\dsh-safe-restart.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -DryRun 2>&1 |
    Where-Object { $_ -match 'FAIL|failed|ABORT|exit code' } |
    ForEach-Object { Write-Host "  $_" }

Write-Host ''
Write-Host '  环境就绪。录屏步骤：' -ForegroundColor Green
Write-Host '    .\demo-1-before.ps1' -ForegroundColor White
Write-Host '    .\dsh-safe-restart.ps1 -DryRun' -ForegroundColor White
Write-Host '    重启 DSH（不预检），看它降级' -ForegroundColor White
Write-Host '    .\demo-2-after.ps1' -ForegroundColor White
Write-Host '    .\demo-restore.ps1' -ForegroundColor White
Write-Host ''
if (-not $KeepBroken) {
    Write-Host '  ⚠ 现在这台 DSH 一重启就会崩。录完记得跑 demo-restore.ps1' -ForegroundColor Red
    Write-Host ''
}
