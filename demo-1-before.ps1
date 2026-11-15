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

    Write-Host '  node_modules 目录数（含传递依赖）' -ForegroundColor DarkGray
    Write-Host ("    {0} 个" -f $pluginN) -ForegroundColor White
    Write-Host ''

    Line
    Write-Host ''
    Write-Host '  下一步：双击 3-检查并重启.cmd' -ForegroundColor Yellow
    Write-Host '    会弹出检查窗口，标出哪个插件加载不了，并且拦住重启' -ForegroundColor White
    Write-Host ''
    Write-Host '  对照实验：不管它，直接重启 DSH，然后跑 4-看惨状.cmd' -ForegroundColor Yellow
    Write-Host '    你会看到 bundles 从 28 变成 2，patch 从 197 行变成 661 B' -ForegroundColor White
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

    Write-Host '  node_modules 目录数（含传递依赖）' -ForegroundColor DarkGray
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
