# demo-restore.ps1 —— 一键恢复演示造成的改动
# 用法：powershell -ExecutionPolicy Bypass -File D:\dpsk\projects\dsh-safe-restart\demo-restore.ps1

$ErrorActionPreference = 'Stop'
$profileDir = 'C:\Users\Admin1\.dsh\profiles\desktop'
$pkg = Join-Path $profileDir 'package.json'
$bak = 'D:\dpsk\backup\demo-20261116\package.json.good'

Write-Host '=== 恢复演示配置 ===' -ForegroundColor Cyan

# 1. 从 bundles 里移除 demo-broken-plugin
$j = Get-Content $pkg -Raw | ConvertFrom-Json
$before = $j.dsh.profile.bundles.Count
$j.dsh.profile.bundles = @($j.dsh.profile.bundles | Where-Object { $_ -ne 'demo-broken-plugin' })
$after = $j.dsh.profile.bundles.Count
[IO.File]::WriteAllText($pkg, ($j | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
Write-Host ("bundles: {0} -> {1}" -f $before, $after)

# 2. 删掉演示插件目录
$dir = Join-Path $profileDir 'node_modules\demo-broken-plugin'
if (Test-Path $dir) {
    Remove-Item $dir -Recurse -Force
    Write-Host 'removed: node_modules\demo-broken-plugin'
}

# 3. 校验 dry-run 是否恢复干净
Write-Host ''
Write-Host '=== 复核 dry-run ===' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'D:\dpsk\projects\dsh-safe-restart\dsh-safe-restart.ps1' -DryRun 2>&1 | Select-Object -Last 6
Write-Host ''
Write-Host ('exit code: ' + $LASTEXITCODE) -ForegroundColor Yellow
