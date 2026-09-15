# App Icon Generator (Windows / PowerShell)
# 与 generate_icons.sh 行为一致：用 flutter_launcher_icons 生成全平台图标。
# 用法（PowerShell 7 / Windows PowerShell）：
#   powershell -ExecutionPolicy Bypass -File .\generate_icons.ps1
# 前置条件：先把 1024x1024 图标放到 flutter_launcher_icons.yaml 中 image_path 指定的位置。

$ErrorActionPreference = 'Stop'

Write-Host "=======================================" -ForegroundColor Blue
Write-Host "    Flutter App Icon Generator        " -ForegroundColor Blue
Write-Host "=======================================" -ForegroundColor Blue
Write-Host ""

if (-not (Test-Path -LiteralPath 'flutter_launcher_icons.yaml')) {
    Write-Host 'Error: flutter_launcher_icons.yaml not found!' -ForegroundColor Red
    Write-Host 'Please make sure you have the configuration file in the root directory.' -ForegroundColor Yellow
    exit 1
}

# 从 yaml 里取第一个 image_path
$yaml = [System.IO.File]::ReadAllText('flutter_launcher_icons.yaml')
$iconPath = $null
if ($yaml -match '(?m)^\s*image_path:\s*"?([^"#\r\n]+?)"?\s*$') {
    $iconPath = $Matches[1].Trim()
}

if (-not $iconPath -or -not (Test-Path -LiteralPath $iconPath)) {
    Write-Host "Warning: Source icon ($iconPath) not found." -ForegroundColor Yellow
    Write-Host "Please ensure you have an icon at $iconPath before running this script." -ForegroundColor Yellow
    Write-Host 'Recommended size: 1024x1024 png'
    Write-Host ""
    $answer = Read-Host 'Do you want to continue anyway? (y/N)'
    if ($answer -cnotmatch '^[Yy]') {
        Write-Host 'Operation canceled.' -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Found source icon at: $iconPath" -ForegroundColor Green
}

Write-Host 'Generating icons for all platforms...' -ForegroundColor Blue
Write-Host ""

& dart run flutter_launcher_icons

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host 'Icons generated successfully!' -ForegroundColor Green
    Write-Host '   - Android: mipmap resources updated'
    Write-Host '   - iOS: Assets.xcassets updated'
    Write-Host '   - Web: icons and manifest updated'
    Write-Host '   - Windows/macOS: icon files updated'
} else {
    Write-Host ""
    Write-Host 'Error generating icons.' -ForegroundColor Red
    exit 1
}
exit 0
