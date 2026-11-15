#Requires -Version 5.1
<#
  dsh-safe-restart-gui.ps1 — 图形化重启预检
  双击运行，弹出窗口列出每个插件的加载状态，坏的用红叉标出。
#>

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$profileDir = 'D:\DSH\data\profiles\desktop'
$pkgPath    = Join-Path $profileDir 'package.json'
$simulate   = Join-Path $PSScriptRoot 'dsh-simulate.mjs'
$nodeExe    = ''

# ---- 找 node ----
$cand = Get-ChildItem "$env:USERPROFILE\.dsh\dsh-runtimes" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'dependencies\node\bin\node.exe' } |
        Where-Object { Test-Path $_ }
if ($cand) { $nodeExe = $cand[0] }
if (-not $nodeExe) { $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source }

# ---- XAML ----
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DSH 重启检查" Height="640" Width="760"
        WindowStartupLocation="CenterScreen"
        Background="#0f1219" ResizeMode="NoResize"
        FontFamily="Microsoft YaHei UI">
  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#161b26" Padding="22,16">
      <StackPanel>
        <TextBlock Text="重启前检查" Foreground="#f2f4f8" FontSize="22" FontWeight="SemiBold"/>
        <TextBlock x:Name="Subtitle" Text="正在读取插件清单…" Foreground="#78808f" FontSize="12" Margin="0,4,0,0"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="1" Background="#12161f" Padding="22,10" BorderBrush="#232837" BorderThickness="0,0,0,1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" x:Name="Counter" Text="0 / 0 已检查" Foreground="#78808f" FontSize="12" VerticalAlignment="Center"/>
        <TextBlock Grid.Column="1" x:Name="Elapsed" Text="" Foreground="#78808f" FontSize="12" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Padding="14,8">
      <StackPanel x:Name="List"/>
    </ScrollViewer>

    <Border Grid.Row="3" Background="#161b26" Padding="22,16" BorderBrush="#232837" BorderThickness="0,1,0,0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock x:Name="Verdict" Text="检查中…" Foreground="#c7cbd6" FontSize="15" FontWeight="SemiBold"/>
          <TextBlock x:Name="VerdictSub" Text="" Foreground="#78808f" FontSize="11" Margin="0,3,0,0"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnCancel" Content="关闭" Width="92" Height="36" Margin="0,0,10,0"
                  Background="#232837" Foreground="#c7cbd6" BorderBrush="#2f3648" FontSize="13"
                  IsEnabled="False"/>
          <Button x:Name="BtnRestore" Content="恢复上次快照" Width="120" Height="36" Margin="0,0,10,0"
                  Background="#2a3040" Foreground="#8a93a6" BorderBrush="#333a4d" FontSize="13"
                  FontWeight="SemiBold" IsEnabled="False" Visibility="Collapsed"/>
          <Button x:Name="BtnRestart" Content="重启 DSH" Width="120" Height="36"
                  Background="#5b79ff" Foreground="White" BorderBrush="#5b79ff" FontSize="13"
                  FontWeight="SemiBold" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)
foreach ($n in 'Subtitle','Counter','Elapsed','List','Verdict','VerdictSub','BtnCancel','BtnRestart','BtnRestore') {
    Set-Variable -Name $n -Scope Script -Value $win.FindName($n)
}

# 最近一次快照
function Get-LatestSnapshot {
    param([string]$Root)
    if (-not (Test-Path $Root)) { return $null }
    $d = Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $d) { return $null }
    $pj = Join-Path $d.FullName 'package.json'
    $cp = Join-Path $d.FullName 'cordis.patch.yml'
    if (-not (Test-Path $pj)) { return $null }
    $n = 0
    try { $n = @((([IO.File]::ReadAllText($pj, [Text.Encoding]::UTF8)) | ConvertFrom-Json).dsh.profile.bundles).Count } catch { return $null }
    return [pscustomobject]@{ Dir = $d.FullName; Name = $d.Name; Bundles = $n; HasPatch = (Test-Path $cp); SourceFile = $pj; IsBackup = $false }
}

function Restart-DshProcess {
    Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.CloseMainWindow() | Out-Null } catch {}
    }
    Start-Sleep -Seconds 3
    Get-Process 'DeepSeek Harness' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process 'D:\deep seek\DeepSeek Harness.exe'
}

# 没有快照时的兜底：从 profile 目录里翻 package.json.bak*，挑插件最多的那份
function Get-BestBackup {
    param([string]$Dir)
    if (-not (Test-Path $Dir)) { return $null }
    $cands = @()
    Get-ChildItem $Dir -Filter 'package.json.bak*' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $n = -1
        try {
            $n = @((([IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)) | ConvertFrom-Json).dsh.profile.bundles).Count
        } catch { return }
        if ($n -gt 0) {
            $cands += [pscustomobject]@{
                Dir        = $Dir
                Name       = $_.Name
                Bundles    = $n
                HasPatch   = $false
                SourceFile = $_.FullName
                IsBackup   = $true
            }
        }
    }
    if ($cands.Count -eq 0) { return $null }
    return ($cands | Sort-Object -Property @{Expression='Bundles';Descending=$true}, @{Expression='Name';Descending=$true} | Select-Object -First 1)
}

function New-Row($name, $version, $status, $detail) {
    $border = New-Object Windows.Controls.Border
    $border.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#12161f')
    $border.CornerRadius = 6
    $border.Padding = '12,7'
    $border.Margin = '0,0,0,4'

    $grid = New-Object Windows.Controls.Grid
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'
    $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = '*'
    $c3 = New-Object Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
    $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2); $grid.ColumnDefinitions.Add($c3)

    $icon = New-Object Windows.Controls.TextBlock
    $icon.Text = if ($status -eq 'OK') { '✓' } elseif ($status -eq 'FAIL') { '✕' } else { '·' }
    $icon.FontSize = 14
    $icon.Width = 24
    $icon.VerticalAlignment = 'Center'
    $icon.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString(
        $(if ($status -eq 'OK') { '#4fae6e' } elseif ($status -eq 'FAIL') { '#e05a3a' } else { '#5d6474' }))
    [Windows.Controls.Grid]::SetColumn($icon, 0)
    $grid.Children.Add($icon) | Out-Null

    $stack = New-Object Windows.Controls.StackPanel
    $nm = New-Object Windows.Controls.TextBlock
    $nm.Text = $name
    $nm.FontSize = 13
    $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString(
        $(if ($status -eq 'FAIL') { '#ff8a6b' } else { '#e8ebf2' }))
    if ($status -eq 'HOSTDEP' -or $status -eq 'MISSING') {
        $nm.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6b7383')
    }
    $stack.Children.Add($nm) | Out-Null

    if ($detail) {
        $d = New-Object Windows.Controls.TextBlock
        $d.Text = $detail
        $d.FontSize = 10.5
        $d.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#8a93a6')
        $d.TextWrapping = 'Wrap'
        $d.Margin = '0,2,0,0'
        $stack.Children.Add($d) | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($stack, 1)
    $grid.Children.Add($stack) | Out-Null

    $v = New-Object Windows.Controls.TextBlock
    $v.Text = $version
    $v.FontSize = 11
    $v.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#5d6474')
    $v.VerticalAlignment = 'Center'
    $v.Margin = '10,0,0,0'
    [Windows.Controls.Grid]::SetColumn($v, 2)
    $grid.Children.Add($v) | Out-Null

    $border.Child = $grid
    return $border
}

# ---- 检查 ----
$sw = [Diagnostics.Stopwatch]::StartNew()
$failList = @()
$pkgPath = Join-Path $profileDir 'package.json'

try {
    $Subtitle.Text = "正在逐个 import 每个插件…"
    $win.Dispatcher.Invoke([action]{}, 'Background')

    $json = $null
    if (Test-Path $simulate) {
        $out = & $nodeExe $simulate $profileDir --json 2>&1
        $line = $out | Where-Object { $_ -like '__JSON__*' } | Select-Object -First 1
        if ($line) { $json = ($line -replace '^__JSON__', '') | ConvertFrom-Json }
    }
    if (-not $json) { throw "dsh-simulate.mjs 没有返回结果" }

    $Subtitle.Text = "共 $($json.total) 个插件 · $profileDir"
    $Counter.Text = "$($json.total) / $($json.total) 已检查"

    # 有问题的排前面
    $sorted = @($json.rows | Sort-Object -Property @{
        Expression = {
            if ($_.status -eq 'FAIL' -or $_.status -eq 'BAD-PKG' -or $_.status -eq 'NO-ENTRY') { 0 }
            elseif ($_.status -eq 'MISSING') { 1 }
            else { 2 }
        }
    })

    foreach ($r in $sorted) {
        $List.Children.Add((New-Row $r.name $r.ver $r.status $r.detail)) | Out-Null
        if ($r.status -eq 'FAIL' -or $r.status -eq 'BAD-PKG' -or $r.status -eq 'NO-ENTRY') {
            $failList += $r.name
        }
    }
}
catch {
    $Verdict.Text = '检查过程出错'
    $VerdictSub.Text = $_.Exception.Message
    $Verdict.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#e05a3a')
    $BtnCancel.IsEnabled = $true
    $win.ShowDialog() | Out-Null
    return
}

$sw.Stop()
$Elapsed.Text = ('{0:N1} 秒' -f $sw.Elapsed.TotalSeconds)

$snapRoot = Join-Path $env:LOCALAPPDATA 'dsh-safe-restart\snapshots'
$snap = Get-LatestSnapshot $snapRoot
$curCount = 0
try { $curCount = @((([IO.File]::ReadAllText($pkgPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json).dsh.profile.bundles).Count } catch {}

if ($failList.Count -eq 0) {
    $Verdict.Text = '全部插件可正常加载'
    $VerdictSub.Text = '可以安全重启'
    $Verdict.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#4fae6e')
    $BtnRestart.IsEnabled = $true
}
else {
    $Verdict.Text = "$($failList.Count) 个插件无法加载"
    $VerdictSub.Text = '点右边：把它们从启动清单里停用，然后重启'
    $Verdict.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#e05a3a')
    $BtnRestart.IsEnabled = $true
    $BtnRestart.Content = '停用并重启'
    $BtnRestart.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#c2603a')
    $BtnRestart.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#c2603a')
    $BtnRestart.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#ffffff')
}

# 快照恢复：当前明显比快照少，或者查出了问题，就给这个按钮
$restoreFrom = $null
$restoreLabel = ''
if ($snap) { $restoreFrom = $snap; $restoreLabel = '快照' }
else {
    $bak = Get-BestBackup $profileDir
    if ($bak) { $restoreFrom = $bak; $restoreLabel = '备份' }
}

if ($restoreFrom -and ($curCount -lt $restoreFrom.Bundles -or $failList.Count -gt 0)) {
    $BtnRestore.Visibility = 'Visible'
    $BtnRestore.IsEnabled = $true
    $BtnRestore.Content = "恢复$restoreLabel $($restoreFrom.Bundles) 个"
    $BtnRestore.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#232837')
    $BtnRestore.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#4fae6e')
    $BtnRestore.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#8ed4a4')
    if ($curCount -lt $restoreFrom.Bundles) {
        $VerdictSub.Text = "现在只有 $curCount 个插件 · ${restoreLabel}里有 $($restoreFrom.Bundles) 个"
        $BtnRestart.IsEnabled = $false
        $BtnRestart.Content = '无法重启'
        $BtnRestart.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#2a3040')
        $BtnRestart.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#333a4d')
        $BtnRestart.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#6b7383')
    }
}
$BtnCancel.IsEnabled = $true

$BtnCancel.Add_Click({ $win.Close() })

$BtnRestore.Add_Click({
    if (-not $restoreFrom) { return }
    try {
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $pkgPath "$pkgPath.bak-restore-$ts" -Force -ErrorAction SilentlyContinue
        Copy-Item $restoreFrom.SourceFile $pkgPath -Force
        $patchPath = Join-Path $profileDir 'cordis.patch.yml'
        if ($restoreFrom.HasPatch) {
            Copy-Item $patchPath "$patchPath.bak-restore-$ts" -Force -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $restoreFrom.Dir 'cordis.patch.yml') $patchPath -Force
        }
    }
    catch {
        [Windows.MessageBox]::Show("恢复失败，没有重启：`n`n$($_.Exception.Message)", '出错', 'OK', 'Error') | Out-Null
        return
    }
    $win.Close()
    Restart-DshProcess
})

$BtnRestart.Add_Click({
    if ($failList.Count -gt 0) {
        try {
            $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
            Copy-Item $pkgPath "$pkgPath.bak-gui-$ts" -Force
            $j = ([IO.File]::ReadAllText($pkgPath, [Text.Encoding]::UTF8)) | ConvertFrom-Json
            $keep = @($j.dsh.profile.bundles | Where-Object { $failList -notcontains $_ })
            $j.dsh.profile.bundles = $keep
            $json = $j | ConvertTo-Json -Depth 100
            [IO.File]::WriteAllText($pkgPath, $json, (New-Object Text.UTF8Encoding $false))
        }
        catch {
            [Windows.MessageBox]::Show("停用失败，没有重启：`n`n$($_.Exception.Message)", '出错', 'OK', 'Error') | Out-Null
            return
        }
    }
    $win.Close()
    Restart-DshProcess
})

$win.ShowDialog() | Out-Null
