@echo off
chcp 65001 >nul
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CXXY-CampusNet.ps1"
exit
