#!/usr/bin/env python3
"""Builds assets/sprites.png + sprites.json from 0x72's CC0 DungeonTileset II.

    python3 tools/build-atlas.py path/to/0x72_DungeonTilesetII_v1_3.png

Each job gets its four idle frames, packed into one small PNG. The manifest
records per-frame rectangles plus the display scale, and is consumed by both
js/render.js and godot/scripts/view/BoardView.gd. Requires Pillow.
"""
import json, sys, shutil, os
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "0x72.png"
im = Image.open(SRC).convert("RGBA"); W, H = im.size; px = im.load()

def trim(x0, y0, w, h):
    """Alpha-trim a crop window to its content bounds; returns (x, y, w, h)."""
    xs = [x for x in range(x0, x0 + w) for y in range(y0, y0 + h) if px[x, y][3] > 0]
    ys = [y for x in range(x0, x0 + w) for y in range(y0, y0 + h) if px[x, y][3] > 0]
    if not xs: raise SystemExit(f"empty frame at {x0},{y0}")
    return (min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1)

# Frames sit on a fixed horizontal stride (idle frames first, run frames after),
# but row heights vary, so row extents are measured from the pixels: each
# contiguous band of non-empty pixel rows in a character column is one character.
def bands(x0, x1):
    filled = [any(px[x, y][3] > 0 for x in range(x0, x1)) for y in range(H)]
    out, y = [], 0
    while y < H:
        if filled[y]:
            top = y
            while y < H and filled[y]: y += 1
            out.append((top, y - top))
        else: y += 1
    return out
HERO = (128, 16, bands(128, 144))     # elf_f, elf_m, knight_f, knight_m, wizzard_f, wizzard_m, lizard_f, lizard_m, (big-monster bleed), elf
MON  = (368, 16, bands(368, 384))     # tiny_zombie, goblin, imp, skelet, muddy, swampy, masked_orc, orc_warrior, orc_shaman, necromancer, wogol, chort, pet
BIG  = (16, 32, bands(16, 48))        # big_zombie, ogre, big_demon (below the wall/floor tiles)
print("hero rows:", HERO[2]); print("monster rows:", MON[2]); print("big rows:", BIG[2])

def row(col, index):
    x0, stride, rows = col
    top, h = rows[index]
    frames = [trim(x0 + k * stride, top, stride, h) for k in range(4)]
    y0 = min(f[1] for f in frames); y1 = max(f[1] + f[3] for f in frames)
    return [(f[0], y0, f[2], y1 - y0) for f in frames]

# job -> (column, row index)
MAP = {
    "Knight":      row(HERO, 3),   # knight_m
    "HolyKnight":  row(HERO, 2),   # knight_f
    "Archer":      row(HERO, 0),   # elf_f
    "Mage":        row(HERO, 5),   # wizzard_m
    "Priest":      row(HERO, 4),   # wizzard_f
    "Bandit":      row(HERO, 1),   # elf_m
    "Merchant":    row(HERO, 6),   # lizard_f — a small traveller
    "Goblin":      row(MON, 1),
    "Orc":         row(MON, 7),    # orc_warrior
    "DarkKnight":  row(MON, 6),    # masked_orc
    "Shade":       row(MON, 4),    # muddy — the dark floating one
    "Skeleton":    row(MON, 3),    # skelet
    "Necromancer": row(MON, 9),
    "Dragon":      row(BIG, len(BIG[2]) - 1),    # big_demon (last big row)
}

# Pack: one row per job, frames side by side, 1px gutters.
pad = 1; cells = {}; y = pad; width = 0
for job, frames in MAP.items():
    w = max(f[2] for f in frames); h = max(f[3] for f in frames)
    cells[job] = {"frames": [], "w": w, "h": h}
    width = max(width, pad + 4 * (w + pad)); y += h + pad
atlas = Image.new("RGBA", (width, y), (0, 0, 0, 0)); y = pad
for job, frames in MAP.items():
    c = cells[job]; x = pad
    for (fx, fy, fw, fh) in frames:
        crop = im.crop((fx, fy, fx + fw, fy + fh))
        # bottom-align inside the job's cell so feet line up across frames
        atlas.paste(crop, (x + (c["w"] - fw) // 2, y + c["h"] - fh), crop)
        c["frames"].append({"x": x, "y": y, "w": c["w"], "h": c["h"]})
        x += c["w"] + pad
    y += c["h"] + pad

os.makedirs("assets", exist_ok=True)
atlas.save("assets/sprites.png")
manifest = {
    "enabled": True, "image": "assets/sprites.png", "scale": 2.2, "fps": 6,
    "source": "0x72 DungeonTileset II v1.3 (CC0) — https://0x72.itch.io/dungeontileset-ii",
    "cells": cells,
}
json.dump(manifest, open("assets/sprites.json", "w"), indent=1)
os.makedirs("godot/assets", exist_ok=True)
shutil.copy("assets/sprites.png", "godot/assets/sprites.png")
shutil.copy("assets/sprites.json", "godot/assets/sprites.json")
print(f"atlas {atlas.size[0]}x{atlas.size[1]}, {len(cells)} jobs")
# 4x preview with labels for eyeballing the mapping
from PIL import ImageDraw
S = 4; pv = Image.new("RGBA", (atlas.size[0] * S + 120, atlas.size[1] * S), (30, 30, 40, 255))
pv.alpha_composite(atlas.resize((atlas.size[0] * S, atlas.size[1] * S), Image.NEAREST))
d = ImageDraw.Draw(pv)
for job, c in cells.items(): d.text((atlas.size[0] * S + 6, c["frames"][0]["y"] * S), job, fill=(255, 255, 0, 255))
pv.save(sys.argv[2] if len(sys.argv) > 2 else "/tmp/atlas-preview.png")
