$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$profileDir = 'D:\DSH\data\profiles\desktop'
$snapRoot   = Join-Path $env:LOCALAPPDATA 'dsh-safe-restart\snapshots'
$preCrash   = Join-Path $profileDir 'cordis.patch.yml.bak-before-crash'

$srcPatch = $null
$srcLabel = ''

if (Test-Path $preCrash) {
  $srcPatch = $preCrash
  $srcLabel = '崩溃前的自动备份 (.bak-before-crash)'
} else {
  $snap = Get-ChildItem $snapRoot -Directory -ErrorAction SilentlyContinue |
          Sort-Object Name -Descending |
          Where-Object { Test-Path (Join-Path $_.FullName 'cordis.patch.yml') } |
          Select-Object -First 1
  if ($snap) { $srcPatch = Join-Path $snap.FullName 'cordis.patch.yml'; $srcLabel = "快照 $($snap.Name)" }
}

if (-not $srcPatch) { Write-Host '没找到可用的备份，无法修复' -ForegroundColor Red; exit 1 }

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item (Join-Path $profileDir 'cordis.patch.yml') (Join-Path $profileDir "cordis.patch.yml.bak-fix-$ts") -Force
Copy-Item $srcPatch (Join-Path $profileDir 'cordis.patch.yml') -Force

$pl = (Get-Content (Join-Path $profileDir 'cordis.patch.yml') -Encoding UTF8).Count
$j  = Get-Content (Join-Path $profileDir 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$n  = @($j.dsh.profile.bundles).Count

Write-Host ''
Write-Host "  已修复 cordis.patch.yml" -ForegroundColor Green
Write-Host "    来源    : $srcLabel" -ForegroundColor Gray
Write-Host "    patch   : $pl 行" -ForegroundColor White
Write-Host "    bundles : $n 项" -ForegroundColor White
Write-Host ''
Write-Host '  现在重新打开 DSH，应该能正常启动了。' -ForegroundColor Yellow
Write-Host ''
