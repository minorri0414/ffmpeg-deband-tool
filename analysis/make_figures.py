#!/usr/bin/env python3
"""
make_figures.py —— 生成 README 里的示意图

全部用合成素材，不含任何视频截帧：
  1. banding-concept.png  色带是怎么来的（8-bit 量化 / 去色带后）
  2. blur-dither.png      blur=1 与 blur=0 的抖动对比
  3. coupling-chroma.png  coupling 对色度去色带的影响（真实 U 平面）

需要：ffmpeg（带 deband、extractplanes 滤镜）、Pillow、numpy。

用法：
    python make_figures.py --out ../docs/images

许可证：GPL-3.0-or-later
"""

import argparse
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 760, 420
FONT_CANDIDATES = [
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/System/Library/Fonts/PingFang.ttc",
]


def font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                continue
    return ImageFont.load_default()


def banded_gradient(levels=22):
    """暗部渐变（亮度 50~118），量化成 levels 级 —— 模拟真实场景里的色带。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 0.20 + 0.26 * (xx / W) + 0.05 * (yy / H)
    v = np.round(v * levels) / levels
    return (v * 255).astype(np.uint8)


def run_deband(src_png, dst_png, thr=0.065, rng=28, blur=0, cpl=0):
    chain = (f"deband=1thr={thr}:2thr={thr}:3thr={thr}:"
             f"range={rng}:blur={blur}:coupling={cpl}")
    subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", "-i", src_png,
                    "-vf", f"format=yuv420p10le,{chain},format=gray", dst_png], check=True)


def load_gray(path):
    return np.asarray(Image.open(path).convert("L")).astype(np.float32)


def stretch(arrays, gamma=1.0):
    """把一组图按共同范围线性拉到 0-255，保证面板之间可比、且不截断。"""
    lo = min(a.min() for a in arrays)
    hi = max(a.max() for a in arrays)
    span = max(hi - lo, 1e-6)
    out = []
    for a in arrays:
        v = np.clip((a - lo) / span, 0, 1) ** gamma
        out.append((v * 255).astype(np.uint8))
    return out


def label(img, text, sub=None):
    img = img.convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")
    f1, f2 = font(21), font(15)
    pad, lh = 10, 28
    box_h = pad * 2 + lh + (lh - 4 if sub else 0)
    d.rectangle([0, 0, img.width, box_h], fill=(0, 0, 0, 180))
    d.text((pad, pad - 2), text, font=f1, fill=(255, 255, 255, 255))
    if sub:
        d.text((pad, pad + lh - 2), sub, font=f2, fill=(205, 205, 205, 255))
    return img


def hstack(panels, gap=2):
    w = sum(p.width for p in panels) + gap * (len(panels) - 1)
    h = max(p.height for p in panels)
    out = Image.new("RGB", (w, h), (12, 12, 12))
    x = 0
    for p in panels:
        out.paste(p, (x, 0))
        x += p.width + gap
    return out


def fig_concept(tmp, outdir):
    src = os.path.join(tmp, "banded.png")
    Image.fromarray(banded_gradient(), "L").save(src)
    deb = os.path.join(tmp, "deb.png")
    run_deband(src, deb, blur=0)

    be, af = load_gray(src), load_gray(deb)
    be, af = stretch([be, af])
    panels = [
        label(Image.fromarray(be, "L"), "① 8-bit 量化后",
              "暗部渐变只剩十几个灰阶 → 台阶"),
        label(Image.fromarray(af, "L"), "② 去色带后",
              "台阶被打散，过渡重新连续"),
    ]
    hstack(panels).save(os.path.join(outdir, "banding-concept.png"))
    print("  banding-concept.png")


def fig_blur(tmp, outdir):
    src = os.path.join(tmp, "banded2.png")
    Image.fromarray(banded_gradient(), "L").save(src)
    b1 = os.path.join(tmp, "b1.png")
    b0 = os.path.join(tmp, "b0.png")
    run_deband(src, b1, blur=1)
    run_deband(src, b0, blur=0)

    z1, z0 = stretch([load_gray(b1), load_gray(b0)])
    panels = [
        label(Image.fromarray(z1, "L"), "blur=1（默认）",
              "过渡被模糊铺开 → 满屏细麻点，看着「脏」"),
        label(Image.fromarray(z0, "L"), "blur=0（推荐）",
              "直接填充 → 过渡连续，没有麻点"),
    ]
    hstack(panels).save(os.path.join(outdir, "blur-dither.png"))
    print("  blur-dither.png")


def fig_coupling(tmp, outdir):
    """亮度几乎不变、色度有大台阶的暗部蓝紫渐变（模拟舞台地板）。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ramp = np.clip(0.15 + 0.7 * (xx / W) + 0.15 * (yy / H), 0, 1)
    chroma = np.round(ramp * 12) / 12          # 色度只有 13 级 → 台阶很宽

    r = 60 + chroma * 70
    g = 40 + chroma * 30
    b = 90 + chroma * 110
    rgb = np.dstack([r, g, b]).clip(0, 255).astype(np.uint8)
    src = os.path.join(tmp, "cpl_src.png")
    Image.fromarray(rgb, "RGB").save(src)

    outs = {}
    for name, cpl in (("c1", 1), ("c0", 0)):
        dst = os.path.join(tmp, f"cpl_{name}.png")
        chain = ("deband=1thr=0.065:2thr=0.065:3thr=0.065:"
                 f"range=28:blur=0:coupling={cpl}")
        subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", "-i", src,
                        "-vf", f"format=yuv420p10le,{chain}", dst], check=True)
        outs[name] = dst

    def u_plane(png, deband_args=None):
        """在同一条滤镜链里转 YUV 并抽出 U 平面，避免 RGB 往返丢掉色度台阶。"""
        chain = "format=yuv420p10le"
        if deband_args:
            chain += "," + deband_args + ",format=yuv420p10le"
        chain += ",extractplanes=u,format=gray,scale=iw*2:ih*2:flags=neighbor"
        tmpu = os.path.join(tmp, "u.png")
        subprocess.run(["ffmpeg", "-hide_banner", "-v", "error", "-y", "-i", png,
                        "-vf", chain, tmpu], check=True)
        return load_gray(tmpu)

    d1 = "deband=1thr=0.065:2thr=0.065:3thr=0.065:range=28:blur=0:coupling=1"
    d0 = "deband=1thr=0.065:2thr=0.065:3thr=0.065:range=28:blur=0:coupling=0"
    us = [u_plane(src), u_plane(src, d1), u_plane(src, d0)]
    us = stretch(us)
    panels = [
        label(Image.fromarray(us[0], "L"), "原始（只看色度 U）",
              "色度只有十几级 → 台阶很宽"),
        label(Image.fromarray(us[1], "L"), "coupling=1（默认）",
              "色度被判定「不用处理」，几乎没变"),
        label(Image.fromarray(us[2], "L"), "coupling=0（推荐）",
              "色度独立处理，台阶被打散"),
    ]
    hstack(panels).save(os.path.join(outdir, "coupling-chroma.png"))
    print("  coupling-chroma.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/images")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    print("生成示意图：")
    with tempfile.TemporaryDirectory() as tmp:
        fig_concept(tmp, args.out)
        fig_blur(tmp, args.out)
        fig_coupling(tmp, args.out)
    print(f"完成，输出到 {args.out}")


if __name__ == "__main__":
    main()


