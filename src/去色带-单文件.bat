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
title 视频去色带工具（单文件版）
setlocal enabledelayedexpansion
color 0F

rem ============ ffmpeg 位置 ============
set "FF=ffmpeg"
where ffmpeg >nul 2>nul
if errorlevel 1 (
    rem 如果 ffmpeg 不在 PATH 里，把下面一行改成你的 ffmpeg.exe 完整路径
    if exist "C:\ffmpeg\bin\ffmpeg.exe" (
        set "FF=C:\ffmpeg\bin\ffmpeg.exe"
    ) else (
        echo.
        echo   [错误] 找不到 ffmpeg.exe
        echo   请把 ffmpeg 加进系统 PATH，或用记事本打开本文件，
        echo   把开头的  set "FF=ffmpeg"  改成 ffmpeg.exe 的完整路径。
        echo.
        pause
        exit /b 1
    )
)

rem ============ 滤镜链 ============
set "VF1=format=yuv420p10le,deband=1thr=0.065:2thr=0.065:3thr=0.065:range=28:blur=0:coupling=0"
set "VF2=%VF1%,format=yuv420p"
set "VF5=%VF1%,zscale=rin=limited:tin=bt709:min=bt709:pin=bt709:t=arib-std-b67:m=bt2020nc:p=bt2020:r=limited:npl=100"
set "X265P=aq-mode=3:aq-strength=1.0:log-level=error"
set "X265HDR=aq-mode=3:aq-strength=1.0:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:range=limited:log-level=error"

echo ============================================
echo            视 频 去 色 带（单文件版）
echo ============================================
echo.

rem ============ 取输入文件 ============
set "IN=%~1"
if defined IN goto :havefile

echo   正在打开文件选择框；没弹出来就直接粘贴路径。
call :pick
if defined IN goto :havefile
echo.
set /p "IN=  请粘贴视频完整路径后回车: "

:havefile
set "IN=%IN:"=%"
if not exist "%IN%" (
    echo.
    echo   [错误] 文件不存在：%IN%
    echo.
    pause
    exit /b 1
)
for %%F in ("%IN%") do (
    set "BASE=%%~dpnF"
    set "FNAME=%%~nxF"
)
echo.
echo   输入：!FNAME!
echo.

rem ============ 命令行直接指定模式（第 2 个参数） ============
set "QUIET=0"
set "MODE="
if not "%~2"=="" (
    set "MODE=%~2"
    if "!MODE!"=="1" set "QUIET=1"
    if "!MODE!"=="2" set "QUIET=1"
    if "!MODE!"=="3" set "QUIET=1"
    if "!MODE!"=="4" set "QUIET=1"
    if "!MODE!"=="5" set "QUIET=1"
    if "!QUIET!"=="0" (
        echo   第 2 个参数只能是 1-5，收到：!MODE!
        echo.
        set "MODE="
    )
)
if defined MODE goto :dispatch

rem ============ 菜单 ============
:menu
echo   请选择输出：
echo.
echo     [1] 10-bit HEVC 母版    最高画质，自己看用这个（推荐）
echo     [2] 8-bit H.264 兼容版  剪辑/上传/手机/老电脑都能放
echo     [3] 只做 20 秒样片      先看效果，约 2 分钟
echo     [4] 硬件加速（NVENC）    3 分钟出片，快 5-8 倍
echo     [5] HLG HDR             杜比视界 / HDR 屏用
echo     [0] 退出
echo.
set "MODE="
set /p "MODE=  输入数字后回车: "
echo.

:dispatch
if "!MODE!"=="0" goto :eof
if "!MODE!"=="1" goto :enc1
if "!MODE!"=="2" goto :enc2
if "!MODE!"=="3" goto :enc3
if "!MODE!"=="4" goto :enc4
if "!MODE!"=="5" goto :enc5
echo   请输入 0-5 之间的数字。
echo.
goto :menu

rem ============ 1. 10-bit 母版 ============
:enc1
set "OUT=!BASE! (deband).mp4"
call :noclobber
echo.
echo   开始编码。1440p60 大约 15-20 分钟，中途不要关窗口。
echo   --------------------------------------------
"%FF%" -hide_banner -y -stats -i "%IN%" -map 0:v:0 -map 0:a? -vf "%VF1%" -c:v libx265 -preset medium -crf 17 -pix_fmt yuv420p10le -x265-params "%X265P%" -tag:v hvc1 -c:a copy -movflags +faststart "%OUT%"
if errorlevel 1 ( echo. & echo   [失败] 编码出错，看上面的报错。 & if "!QUIET!"=="0" pause & exit /b 1 )
goto :done

rem ============ 2. 8-bit 兼容版 ============
:enc2
set "OUT=!BASE! (deband 8bit).mp4"
call :noclobber
echo.
echo   开始编码。大约 3-5 分钟。
echo   --------------------------------------------
"%FF%" -hide_banner -y -stats -i "%IN%" -map 0:v:0 -map 0:a? -vf "%VF2%" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -profile:v high -level 5.1 -c:a copy -movflags +faststart "%OUT%"
if errorlevel 1 ( echo. & echo   [失败] 编码出错，看上面的报错。 & if "!QUIET!"=="0" pause & exit /b 1 )
goto :done

rem ============ 3. 20 秒样片 ============
:enc3
set "OUT=!BASE! (deband 样片).mp4"
call :noclobber
echo.
echo   从第 60 秒开始做 20 秒样片，约 2 分钟。
echo   --------------------------------------------
"%FF%" -hide_banner -y -stats -ss 60 -t 20 -i "%IN%" -map 0:v:0 -map 0:a? -vf "%VF1%" -c:v libx265 -preset medium -crf 17 -pix_fmt yuv420p10le -x265-params "%X265P%" -tag:v hvc1 -c:a copy -movflags +faststart "%OUT%"
if errorlevel 1 ( echo. & echo   [失败] 编码出错，看上面的报错。 & if "!QUIET!"=="0" pause & exit /b 1 )
goto :done

rem ============ 4. 硬件加速 ============
:enc4
set "OUT=!BASE! (deband 硬件).mp4"
call :noclobber
"%FF%" -hide_banner -encoders 2>&1 | findstr /c:"hevc_nvenc" >nul
if errorlevel 1 (
    echo.
    echo   [错误] 这个 ffmpeg 不带 hevc_nvenc，用不了硬件加速，请改用模式 1。
    echo.
    if "!QUIET!"=="0" pause
    exit /b 1
)
echo.
echo   开始编码（GPU）。大约 3 分钟。
echo   --------------------------------------------
"%FF%" -hide_banner -y -stats -i "%IN%" -map 0:v:0 -map 0:a? -vf "%VF1%" -c:v hevc_nvenc -preset p7 -tune hq -rc vbr -cq 17 -b:v 0 -spatial-aq 1 -aq-strength 12 -multipass 2 -rc-lookahead 32 -pix_fmt yuv420p10le -tag:v hvc1 -c:a copy -movflags +faststart "%OUT%"
if errorlevel 1 ( echo. & echo   [失败] 编码出错，看上面的报错。 & if "!QUIET!"=="0" pause & exit /b 1 )
goto :done

rem ============ 5. HLG ============
:enc5
set "OUT=!BASE! (deband HLG).mp4"
call :noclobber
echo.
echo   开始编码。BT.2020 + HLG，1440p60 大约 15-20 分钟。
echo   --------------------------------------------
"%FF%" -hide_banner -y -stats -i "%IN%" -map 0:v:0 -map 0:a? -vf "%VF5%" -c:v libx265 -preset medium -crf 17 -pix_fmt yuv420p10le -x265-params "%X265HDR%" -color_primaries bt2020 -color_trc arib-std-b67 -colorspace bt2020nc -color_range tv -tag:v hvc1 -c:a copy -movflags +faststart "%OUT%"
if errorlevel 1 ( echo. & echo   [失败] 编码出错，看上面的报错。 & if "!QUIET!"=="0" pause & exit /b 1 )
goto :done

rem ============ 完成 ============
:done
echo.
echo   --------------------------------------------
if not exist "%OUT%" (
    echo   [警告] 没找到输出文件，可能编码失败了。
    if "!QUIET!"=="0" pause
    exit /b 1
)
for %%A in ("%OUT%") do set "SZ=%%~zA"
set /a "MB=!SZ!/1048576"
if !MB! equ 0 (
    set /a "KB=!SZ!/1024"
    echo   [完成]  大小 !KB! KB
) else (
    echo   [完成]  大小 !MB! MB
)
echo   位置：%OUT%
if "!QUIET!"=="1" exit /b 0
echo.
choice /c YN /n /m "  打开所在文件夹？(Y/N) "
if errorlevel 2 goto :end
explorer /select,"%OUT%"
:end
echo.
pause
exit /b 0

rem ============ 重名保护 ============
:noclobber
if not exist "%OUT%" exit /b 0
set /a "N=2"
:nc_loop
if not exist "!BASE! (deband !N!).mp4" (
    set "OUT=!BASE! (deband !N!).mp4"
    exit /b 0
)
set /a "N+=1"
goto :nc_loop

rem ============ 文件选择框 ============
:pick
for /f "usebackq delims=" %%i in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Filter='*.mp4;*.mkv;*.mov;*.flv;*.ts;*.avi'; if($d.ShowDialog() -eq 'OK'){$d.FileName}"`) do set "IN=%%i"
exit /b 0
