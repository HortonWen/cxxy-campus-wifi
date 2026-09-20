#Requires -Version 5.1
# 在「启动」文件夹创建开机自启快捷方式，开机后台尝试连接并自动登录。
$ErrorActionPreference = 'Stop'

$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'CXXY-Net-Auto.lnk'
$scriptPath = Join-Path $PSScriptRoot 'CXXY-CampusNet.ps1'

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '" -Mode Auto'
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.Description = '成贤学院 Student_CX 校园网自动登录'
$lnk.Save()

Write-Host '已创建开机自启快捷方式：' $lnkPath
Write-Host '取消方法：删除「启动」文件夹中的 CXXY-Net-Auto.lnk。'
