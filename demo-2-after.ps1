param([switch]$After = $true)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$profileDir = 'D:\DSH\data\profiles\desktop'
$pkg        = Join-Path $profileDir 'package.json'
$patch      = Join-Path $profileDir 'cordis.patch.yml'
$logDir     = "$env:APPDATA\@deepseek-ai\dsh-desktop\logs"

function Line($c = '-', $n = 62) { Write-Host ($c * $n) -ForegroundColor DarkGray }
function Head($t) {
    Write-Host ''
    Line '='
    Write-Host "  $t" -ForegroundColor Cyan
    Line '='
    Write-Host ''
}

# ---------- 读取状态 ----------
$j         = Get-Content $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
$bundles   = @($j.dsh.profile.bundles)
$bundleN   = $bundles.Count
$patchLen  = (Get-Content $patch -Encoding UTF8).Count
$patchSize = (Get-Item $patch).Length
$pluginN   = (Get-ChildItem (Join-Path $profileDir 'node_modules') -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ne '.bin' -and $_.Name -notlike '.*' }).Count
$hasBroken = $bundles -contains 'demo-broken-plugin'

# 最近的 web-boot 崩溃日志
$crashes = @()
if (Test-Path $logDir) {
    $crashes = Get-ChildItem $logDir -Filter 'crash-*-web-boot.log' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 3
}

if (-not $After) {
    Head '重启前 · 现状'

    Write-Host '  DSH profile' -ForegroundColor DarkGray
    Write-Host "    $profileDir" -ForegroundColor White
    Write-Host ''

    Write-Host '  package.json  dsh.profile.bundles' -ForegroundColor DarkGray
    Write-Host ("    {0,-4} 项" -f $bundleN) -ForegroundColor White
    if ($hasBroken) {
        Write-Host '    含 demo-broken-plugin（坏的）' -ForegroundColor Red
    }
    Write-Host ''

    Write-Host '  cordis.patch.yml' -ForegroundColor DarkGray
    Write-Host ("    {0} 行 / {1:N0} B" -f $patchLen, $patchSize) -ForegroundColor White
    Write-Host ''

    Write-Host '  node_modules 里的插件包' -ForegroundColor DarkGray
    Write-Host ("    {0} 个" -f $pluginN) -ForegroundColor White
    Write-Host ''

    Line
    Write-Host ''
    Write-Host '  下一步：跑一次预检（它会在重启前拦下来）' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    .\dsh-safe-restart.ps1 -DryRun' -ForegroundColor White
    Write-Host ''
    Write-Host '  再下一步：换成直接重启 DSH（不预检），看会变成什么样' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    重启完再跑：.\demo-after.ps1' -ForegroundColor White
    Write-Host ''
}
else {
    Head '重启后 · 对照'

    Write-Host '  package.json  dsh.profile.bundles' -ForegroundColor DarkGray
    Write-Host ("    {0,-4} 项" -f $bundleN) -ForegroundColor White
    if ($bundleN -le 3) {
        Write-Host '    ← 被降级了' -ForegroundColor Red
    }
    Write-Host ''
    Write-Host '    剩下的：' -ForegroundColor DarkGray
    foreach ($b in $bundles) { Write-Host "      $b" -ForegroundColor Gray }
    Write-Host ''

    Write-Host '  cordis.patch.yml' -ForegroundColor DarkGray
    Write-Host ("    {0} 行 / {1:N0} B" -f $patchLen, $patchSize) -ForegroundColor White
    if ($patchSize -lt 1000) {
        Write-Host '    ← 被重写成最小版本了' -ForegroundColor Red
    }
    Write-Host ''

    Write-Host '  node_modules 里的插件包' -ForegroundColor DarkGray
    Write-Host ("    {0} 个" -f $pluginN) -ForegroundColor White
    Write-Host ''

    Write-Host '  最近的 web-boot 崩溃日志' -ForegroundColor DarkGray
    if ($crashes.Count -eq 0) {
        Write-Host '    没有' -ForegroundColor Gray
    } else {
        foreach ($c in $crashes) {
            Write-Host ("    {0}  {1:N0} B" -f $c.Name, $c.Length) -ForegroundColor Gray
        }
    }
    Write-Host ''

    Line
    Write-Host ''
    Write-Host '  恢复（一条命令回到刚才的样子）' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    .\demo-restore.ps1' -ForegroundColor White
    Write-Host ''
}
