@echo off
rem ===================================================================
rem  ffmpeg-deband-tool  --  FFmpeg 视频去色带工具
rem  Copyright (C) 2026 AngesDitgialIO
rem
rem  本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共
rem  许可证（第 3 版，或你选择的任何更新版本）的条款重新发布和/或修改。
rem  本程序按「无任何担保」分发，详见 LICENSE 文件。
rem ===================================================================
chcp 936 >nul
setlocal
set "PS1=%~dp0去色带.ps1"

if not exist "%PS1%" (
    echo.
    echo   [错误] 同目录下找不到 去色带.ps1
    echo   请确认 bat 和 ps1 两个文件放在一起。
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" pause
exit /b %RC%
