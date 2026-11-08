#!/usr/bin/env python3
"""
measure_banding.py —— 色带（banding）量化测量

思路：把一帧画面取出来，直接读原始 Y/U/V 平面（绕开 ffmpeg 的 TV→PC 范围
转换，否则测量结果会被污染），统计三个指标：

  flat%  相邻样本完全相同的比例。越高说明画面越"一片片"，也就是色带越重。
  run    同色水平连续段的平均长度（像素）。越长说明台阶越宽、越显眼。
  levels 区域内出现的不同灰阶数。

用法：
    python measure_banding.py video.mp4 --time 85
    python measure_banding.py video.mp4 --time 85 --region 0,1040,720,400

依赖：ffmpeg / ffprobe 在 PATH 里，以及 numpy。

许可证：GPL-3.0-or-later
"""

import argparse
import json
import subprocess
import sys

import numpy as np


def probe(path):
    """取视频的宽高与色彩信息。"""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,pix_fmt,color_transfer,color_primaries",
         "-of", "json", path],
        capture_output=True, text=True, check=True).stdout
    st = json.loads(out)["streams"][0]
    return int(st["width"]), int(st["height"])


def grab_planes(path, width, height, timestamp):
    """取指定时间点的 Y/U/V 平面，统一转成 10-bit（TV range 下 8→10 是精确的 ×4）。"""
    p = subprocess.run(
        ["ffmpeg", "-hide_banner", "-v", "error", "-ss", str(timestamp), "-i", path,
         "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"],
        capture_output=True)
    cw, ch = width // 2, height // 2
    expect = width * height + 2 * cw * ch
    data = np.frombuffer(p.stdout, np.uint16)
    if data.size != expect:
        sys.exit(f"[错误] 取帧失败（拿到 {data.size} 个样本，期望 {expect}）"
                 f"\n{p.stderr.decode('utf-8', 'replace')[:400]}")
    data = data.astype(np.int32)
    y = data[:width * height].reshape(height, width)
    u = data[width * height:width * height + cw * ch].reshape(ch, cw)
    v = data[width * height + cw * ch:].reshape(ch, cw)
    return y, u, v


def stats(plane, region=None):
    if region:
        x, y, w, h = region
        plane = plane[y:y + h, x:x + w]
    dx = np.abs(np.diff(plane, axis=1)).ravel()
    dy = np.abs(np.diff(plane, axis=0)).ravel()
    flat = float(((dx == 0).mean() + (dy == 0).mean()) / 2) * 100
    runs = [len(row) / (len(np.flatnonzero(np.diff(row) != 0)) + 1) for row in plane]
    return flat, float(np.mean(runs)), int(len(np.unique(plane)))


def main():
    ap = argparse.ArgumentParser(description="测量视频某一帧的色带指标")
    ap.add_argument("video", help="视频文件")
    ap.add_argument("--time", type=float, default=0, help="时间点（秒）")
    ap.add_argument("--region", default=None,
                    help="测量区域 x,y,w,h；省略则用整帧的 Y，色度取整帧")
    ap.add_argument("--bit-depth", type=int, default=10, choices=[8, 10],
                    help="按几位精度统计，默认 10（能看出 10-bit 输出的真实平滑度）")
    args = ap.parse_args()

    width, height = probe(args.video)
    y, u, v = grab_planes(args.video, width, height, args.time)

    if args.bit_depth == 8:
        y, u, v = [(p + 2) >> 2 for p in (y, u, v)]

    region = None
    if args.region:
        region = tuple(int(x) for x in args.region.split(","))
        if len(region) != 4:
            sys.exit("[错误] --region 需要 4 个数字：x,y,w,h")

    print(f"文件：{args.video}")
    print(f"时间：{args.time}s    分辨率：{width}x{height}    "
          f"统计精度：{args.bit_depth}-bit\n")
    print(f"{'平面':<6}{'flat%':>9}{'run_px':>9}{'levels':>9}")
    print("-" * 33)
    for name, plane in (("Y", y), ("U", u), ("V", v)):
        flat, run, levels = stats(plane, region if name == "Y" else None)
        print(f"{name:<6}{flat:9.1f}{run:9.1f}{levels:9d}")

    print("\n参考：原始 8-bit 素材的暗部渐变一般在 flat 80-95% / run 10-30 px；")
    print("      去色带做得好会降到 flat 40-70% / run 2-6 px。")


if __name__ == "__main__":
    main()
