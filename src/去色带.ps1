# ===================================================================
#  ffmpeg-deband-tool  --  FFmpeg 视频去色带工具
#  Copyright (C) 2026 AngesDitgialIO
#
#  本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共
#  许可证（第 3 版，或你选择的任何更新版本）的条款重新发布和/或修改。
#  本程序按「无任何担保」分发，详见 LICENSE 文件。
# ===================================================================
param(
    [string]$Path,
    [string]$Mode,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936) } catch { }
try { $Host.UI.RawUI.WindowTitle = '视频去色带工具' } catch { }

$VB = "format=yuv420p10le,deband=1thr=0.065:2thr=0.065:3thr=0.065:range=28:blur=0:coupling=0"

function Find-Ffmpeg {
    $c = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    # 如果 ffmpeg 不在 PATH 里，把下面改成你的 ffmpeg.exe 完整路径
    $cands = @(
        'C:\ffmpeg\bin\ffmpeg.exe'
    )
    foreach ($p in $cands) { if (Test-Path $p) { return $p } }
    return $null
}

function Show-Banner {
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor DarkCyan
    Write-Host "              视 频 去 色 带 工 具" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor DarkCyan
    Write-Host ""
}

Show-Banner

$ff = Find-Ffmpeg
if (-not $ff) {
    Write-Host "  [错误] 找不到 ffmpeg.exe" -ForegroundColor Red
    Write-Host "  请把 ffmpeg 加进系统 PATH，或用记事本打开 去色带.ps1，"
    Write-Host "  把 Find-Ffmpeg 里 cands 那段改成 ffmpeg.exe 的完整路径。"
    if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
    exit 1
}

# ---------------- 选文件 ----------------
if (-not $Path) {
    Write-Host "  请在弹出的窗口里选择视频文件..." -ForegroundColor Gray
    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '选择要去色带的视频'
        $dlg.Filter = '视频文件|*.mp4;*.mkv;*.mov;*.flv;*.ts;*.avi;*.wmv|所有文件|*.*'
        $dlg.Multiselect = $false
        $dlg.RestoreDirectory = $true
        if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-Host "  已取消。" -ForegroundColor Yellow
            if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
            exit 0
        }
        $Path = $dlg.FileName
    } catch {
        Write-Host "  [错误] 打不开文件选择框：$($_.Exception.Message)" -ForegroundColor Red
        if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
        exit 1
    }
}

$Path = $Path.Trim('"')
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "  [错误] 文件不存在：$Path" -ForegroundColor Red
    if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
    exit 1
}
$inFile = Get-Item -LiteralPath $Path
$base = [System.IO.Path]::Combine($inFile.DirectoryName, $inFile.BaseName)

Write-Host "  输入：$($inFile.Name)" -ForegroundColor White
Write-Host "  大小：$([math]::Round($inFile.Length / 1MB, 1)) MB" -ForegroundColor Gray
Write-Host ""

# ---------------- 选模式 ----------------
if (-not $Mode) {
    while ($true) {
        Write-Host "  请选择输出：" -ForegroundColor White
        Write-Host ""
        Write-Host "    [1] 10-bit HEVC 母版    效果最好，自己看用这个（推荐）" -ForegroundColor Green
        Write-Host "    [2] 8-bit H.264 兼容版  剪辑/上传/手机/老电脑都能放"
        Write-Host "    [3] 只做 20 秒样片      先看效果，约 2 分钟"
        Write-Host "    [4] 硬件加速（NVENC）    3 分钟出片，快 5-8 倍，色带效果略打折" -ForegroundColor Yellow
        Write-Host "    [5] HLG HDR             杜比视界 / HDR 屏用，BT.2020 输出" -ForegroundColor Magenta
        Write-Host "    [0] 退出"
        Write-Host ""
        $Mode = (Read-Host "  输入数字后回车").Trim()
        if ($Mode -eq '0') { exit 0 }
        if ($Mode -in @('1', '2', '3', '4', '5')) { break }
        Write-Host "  请输入 0-3 之间的数字。" -ForegroundColor Yellow
        Write-Host ""
    }
}

# ---------------- 组装命令 ----------------
$outName = switch ($Mode) {
    '1' { "$($inFile.BaseName) (deband).mp4" }
    '2' { "$($inFile.BaseName) (deband 8bit).mp4" }
    '3' { "$($inFile.BaseName) (deband 样片).mp4" }
    '4' { "$($inFile.BaseName) (deband 硬件).mp4" }
    '5' { "$($inFile.BaseName) (deband HLG).mp4" }
}
$out = [System.IO.Path]::Combine($inFile.DirectoryName, $outName)

if (Test-Path -LiteralPath $out) {
    $n = 2
    while ($true) {
        $cand = [System.IO.Path]::Combine($inFile.DirectoryName, "$($inFile.BaseName) (deband $n).mp4")
        if (-not (Test-Path -LiteralPath $cand)) { $out = $cand; break }
        $n++
    }
}

$common = @('-hide_banner', '-y', '-stats', '-i', $Path, '-map', '0:v:0', '-map', '0:a?')
$tail = @('-c:a', 'copy', '-movflags', '+faststart', $out)

switch ($Mode) {
    '1' {
        Write-Host "  模式：10-bit HEVC 母版（最高画质）" -ForegroundColor Cyan
        Write-Host "  1440p60 大约 15-20 分钟，中途不要关窗口。" -ForegroundColor Gray
        $enc = @('-vf', $VB, '-c:v', 'libx265', '-preset', 'medium', '-crf', '17',
                 '-pix_fmt', 'yuv420p10le',
                 '-x265-params', 'aq-mode=3:aq-strength=1.0:log-level=error',
                 '-tag:v', 'hvc1')
        $argsList = $common + $enc + $tail
    }
    '2' {
        Write-Host "  模式：8-bit H.264 兼容版" -ForegroundColor Cyan
        Write-Host "  大约 3-5 分钟。" -ForegroundColor Gray
        $enc = @('-vf', "$VB,format=yuv420p", '-c:v', 'libx264', '-preset', 'fast',
                 '-crf', '20', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '5.1')
        $argsList = $common + $enc + $tail
    }
    '3' {
        Write-Host "  模式：20 秒样片（从第 60 秒开始）" -ForegroundColor Cyan
        Write-Host "  大约 2 分钟。" -ForegroundColor Gray
        $enc = @('-vf', $VB, '-c:v', 'libx265', '-preset', 'medium', '-crf', '17',
                 '-pix_fmt', 'yuv420p10le',
                 '-x265-params', 'aq-mode=3:aq-strength=1.0:log-level=error',
                 '-tag:v', 'hvc1')
        $argsList = @('-hide_banner', '-y', '-stats', '-ss', '60', '-t', '20', '-i', $Path,
                      '-map', '0:v:0', '-map', '0:a?') + $enc + $tail
    }
    '4' {
        $hasNvenc = ((& $ff -hide_banner -encoders 2>&1 | Out-String) -match 'hevc_nvenc')
        if (-not $hasNvenc) {
            Write-Host "  [错误] 这个 ffmpeg 不带 hevc_nvenc 编码器，用不了硬件加速。" -ForegroundColor Red
            Write-Host "  请改用模式 1。" -ForegroundColor Gray
            if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
            exit 1
        }
        Write-Host "  模式：硬件加速（NVENC / 10-bit HEVC）" -ForegroundColor Cyan
        Write-Host "  大约 3 分钟出片，色带抑制比模式 1 略弱一点点。" -ForegroundColor Gray
        $enc = @('-vf', $VB, '-c:v', 'hevc_nvenc', '-preset', 'p7', '-tune', 'hq',
                 '-rc', 'vbr', '-cq', '17', '-b:v', '0',
                 '-spatial-aq', '1', '-aq-strength', '12',
                 '-multipass', '2', '-rc-lookahead', '32',
                 '-pix_fmt', 'yuv420p10le', '-tag:v', 'hvc1')
        $argsList = $common + $enc + $tail
    }
    '5' {
        Write-Host "  模式：HLG HDR（杜比视界 / HDR 屏）" -ForegroundColor Cyan
        Write-Host "  BT.2020 + HLG，约 15-20 分钟。" -ForegroundColor Gray
        $hdrVf = "$VB,zscale=rin=limited:tin=bt709:min=bt709:pin=bt709:t=arib-std-b67:m=bt2020nc:p=bt2020:r=limited:npl=100"
        $enc = @('-vf', $hdrVf, '-c:v', 'libx265', '-preset', 'medium', '-crf', '17',
                 '-pix_fmt', 'yuv420p10le',
                 '-x265-params', 'aq-mode=3:aq-strength=1.0:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc:range=limited:log-level=error',
                 '-color_primaries', 'bt2020', '-color_trc', 'arib-std-b67',
                 '-colorspace', 'bt2020nc', '-color_range', 'tv',
                 '-tag:v', 'hvc1')
        $argsList = $common + $enc + $tail
    }
    default {
        Write-Host "  [错误] 模式只能是 1-5，收到：$Mode" -ForegroundColor Red
        if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
        exit 1
    }
}

Write-Host "  输出：$([System.IO.Path]::GetFileName($out))" -ForegroundColor Gray
Write-Host "  --------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $ff @argsList
$code = $LASTEXITCODE
$sw.Stop()

Write-Host ""
Write-Host "  --------------------------------------------" -ForegroundColor DarkGray

if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
    Write-Host "  [失败] ffmpeg 返回码 $code，看上面的报错信息。" -ForegroundColor Red
    if (-not $Quiet) { Read-Host "  按回车关闭" | Out-Null }
    exit 1
}

$sz = [math]::Round((Get-Item -LiteralPath $out).Length / 1MB, 1)
$dur = [math]::Round($sw.Elapsed.TotalMinutes, 1)
Write-Host "  [完成]  大小 $sz MB   耗时 $dur 分钟" -ForegroundColor Green
Write-Host "  位置：$out" -ForegroundColor White
Write-Host ""

if (-not $Quiet) {
    $ans = Read-Host "  打开所在文件夹？(Y/N)"
    if ($ans -match '^[Yy]') { explorer.exe "/select,$out" }
    Read-Host "  按回车关闭" | Out-Null
}
exit 0

