#Requires -Version 5.1
param(
    [switch]$SkipIcon
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$SdkDir = Join-Path $Root 'webview2-sdk'
$WinFormsDll = Join-Path $SdkDir 'lib\net462\Microsoft.Web.WebView2.WinForms.dll'
$CoreDll = Join-Path $SdkDir 'lib\net462\Microsoft.Web.WebView2.Core.dll'
$Loader = Join-Path $SdkDir 'runtimes\win-x64\native\WebView2Loader.dll'

# 1. 需要时下载并解压 WebView2 SDK（NuGet 官方包）
if (-not (Test-Path $WinFormsDll)) {
    Write-Host '下载 WebView2 SDK ...'
    $index = Invoke-RestMethod -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json' -TimeoutSec 30
    $ver = @($index.versions | Where-Object { $_ -notmatch '-' })[-1]
    $nupkg = Join-Path $env:TEMP "microsoft.web.webview2.$ver.nupkg"
    Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$ver/microsoft.web.webview2.$ver.nupkg" -OutFile $nupkg -TimeoutSec 60
    New-Item -ItemType Directory -Path $SdkDir -Force | Out-Null
    tar -xf $nupkg -C $SdkDir
    Remove-Item -LiteralPath $nupkg -Force
}

# 2. 生成多尺寸应用图标
if (-not $SkipIcon) {
    & (Join-Path $Root 'make-icon.ps1') | Out-Null
}

# 3. 用 .NET Framework 自带编译器 csc 编译单文件 exe
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw '未找到 .NET Framework 编译器 csc.exe' }
$fw = Split-Path $csc

$html = Join-Path $Root 'src\index.html'
$manifest = Join-Path $Root 'src\app.manifest'
$icon = Join-Path $Root 'icon.ico'
$src = Join-Path $Root 'src\app.cs'
$out = Join-Path $Root 'CXXYNet.exe'

$refs = @(
    "$fw\System.dll", "$fw\System.Core.dll", "$fw\System.Drawing.dll", "$fw\System.Windows.Forms.dll",
    "$fw\System.Security.dll", "$fw\System.Web.dll", "$fw\System.Web.Extensions.dll", $CoreDll, $WinFormsDll
)

$cscArgs = @('/nologo', '/target:winexe', '/platform:x64', '/optimize+', "/out:$out", "/win32manifest:$manifest", "/win32icon:$icon")
foreach ($r in $refs) { $cscArgs += "/reference:$r" }
$cscArgs += "/resource:$CoreDll,CXXYNet.Res.Core.dll"
$cscArgs += "/resource:$WinFormsDll,CXXYNet.Res.WinForms.dll"
$cscArgs += "/resource:$Loader,CXXYNet.Res.Loader.dll"
$cscArgs += "/resource:$html,CXXYNet.Res.index.html"
$cscArgs += "/resource:$icon,CXXYNet.Res.Icon"
$cscArgs += $src

& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "编译失败 (exit $LASTEXITCODE)" }
Write-Host "编译完成: $out"
