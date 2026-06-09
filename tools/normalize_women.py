#!/usr/bin/env python3
"""
Normalize the raw human illustration art into the per-frame PNGs the app bundles.

Inputs (in the repo root / women_pixal/):
  - walk_right.png, walk_lelf.png  — each a 2508×627 sheet of 4 walk frames on a
    WHITE background (no alpha).
  - women_pixal/stand_left_{1,2,3}.png, stand_right_{1,2,3}.png  — side-profile idle.
  - women_pixal/jumping_{1,2,3}.png        — airborne (held / tumble).
  - women_pixal/sit_down_sad.png, sad.png, sit.png, sitting_dazed_{1,2,3}.png — sitting.

Output: Resources/women/human_*.png — every frame cropped, the white background
keyed out (border flood-fill so her white top/shoes survive), the character
height-normalized so its size is consistent across poses, and bottom-aligned on
one shared canvas (feet on a common baseline). build.sh copies this folder into
the .app bundle; HumanImageArt.swift loads the frames by name.

Run:  python3 tools/normalize_women.py   (needs Pillow)
"""
import os
import glob
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WP = os.path.join(ROOT, "women_pixal")
OUT = os.path.join(ROOT, "Resources", "women")

# role -> (source file stem, flip-to-face-right, target CONTENT height in px).
# Idle/walk are SIDE-PROFILE + SKIRT so they share outfit + angle (no flicker).
ROLES = {
    "idleR1": ("stand_right_1", False, 290), "idleR2": ("stand_right_2", False, 290),
    "idleR3": ("stand_right_3", False, 290),
    "idleL1": ("stand_left_1", False, 290), "idleL2": ("stand_left_2", False, 290),
    "idleL3": ("stand_left_3", False, 290),
    "held": ("jumping_1", False, 300),
    "tumble1": ("jumping_1", False, 300), "tumble2": ("jumping_2", False, 300),
    "tumble3": ("jumping_3", False, 300),
    "impact": ("sit_down_sad", False, 205), "hurt": ("sad", False, 210),
    "getup": ("sit", False, 235),
    "dazed1": ("sitting_dazed_1", False, 210), "dazed2": ("sitting_dazed_2", False, 210),
    "dazed3": ("sitting_dazed_3", False, 210),
}
# 4-frame walk sheets → walkR1..4 / walkL1..4 (split below). Height matches idle.
WALK_SHEETS = {"R": ("walk_right.png", False, 286), "L": ("walk_lelf.png", True, 286)}


def _resolve():
    """Map normalized filename stems to real paths (some files have stray spaces)."""
    found = {}
    for p in glob.glob(os.path.join(WP, "*.png")):
        found[os.path.basename(p).strip().lower().replace(".png", "")] = p
    return found


def key_white(im: Image.Image) -> Image.Image:
    """Make border-connected near-white transparent; keep interior white (top/shoes)."""
    rgb = np.asarray(im.convert("RGB")).astype(int)
    near_white = (rgb[..., 0] > 238) & (rgb[..., 1] > 238) & (rgb[..., 2] > 238)
    h, w = near_white.shape
    bg = np.zeros_like(near_white)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near_white[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near_white[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near_white[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    alpha = np.where(bg, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb.astype(np.uint8), alpha]), "RGBA")


def load_clean(im: Image.Image) -> Image.Image:
    """Crop to content; key the white background first if the image is opaque."""
    im = im.convert("RGBA")
    if im.getchannel("A").getextrema()[0] == 255:   # fully opaque ⇒ white background
        im = key_white(im)
    return im.crop(im.getchannel("A").getbbox())


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, "*.png")):
        os.remove(f)
    real = _resolve()

    frames = {}   # role -> (cropped RGBA, target height)
    for role, (stem, flip, th) in ROLES.items():
        im = load_clean(Image.open(real[stem.lower()]))
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        frames[role] = (im, th)

    for side, (sheet, flip, th) in WALK_SHEETS.items():
        sh = Image.open(os.path.join(ROOT, sheet)).convert("RGBA")
        w, h = sh.size
        fw = w // 4
        for i in range(4):
            im = load_clean(sh.crop((i * fw, 0, (i + 1) * fw, h)))
            if flip:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            frames[f"walk{side}{i + 1}"] = (im, th)

    # Scale each to its target CONTENT height (consistent character size).
    scaled = {}
    for role, (im, th) in frames.items():
        s = th / im.height
        scaled[role] = im.resize((max(1, round(im.width * s)), round(im.height * s)),
                                  Image.LANCZOS)

    cw = max(im.width for im in scaled.values()) + 20
    ch = max(im.height for im in scaled.values()) + 12
    print(f"canvas = {cw}x{ch}  (HumanPixelArt dims ≈ width={round(64 * cw / ch)}, height=64)")

    for role, im in scaled.items():
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        canvas.alpha_composite(im, ((cw - im.width) // 2, ch - im.height))  # bottom-centre
        canvas.save(os.path.join(OUT, f"human_{role}.png"))
    print(f"wrote {len(scaled)} frames to {OUT}")


if __name__ == "__main__":
    main()
