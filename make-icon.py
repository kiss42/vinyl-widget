#!/usr/bin/env python3
"""Generates Resources/AppIcon.icns (a vinyl record). Only needed when the art changes;
the .icns is committed, so building the app never requires Python or Pillow."""
import os, math, shutil, subprocess, sys
try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("needs Pillow:  pip3 install pillow")

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# rounded card with a top-to-bottom gray gradient
card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(card)
for y in range(S):
    t = y / S
    v = int(0xA9 + (0x70 - 0xA9) * t)
    cd.line([(0, y), (S, y)], fill=(v, v, v, 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
img.paste(card, (0, 0), mask)

cx = cy = S / 2
R = S * 0.40
d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=(18, 18, 18, 255))
for i in range(14):                                   # grooves
    r = R * (0.42 + i * 0.041)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 16), width=2)
lr = R * 0.38                                          # label
d.ellipse([cx - lr, cy - lr, cx + lr, cy + lr], fill=(0x1D, 0xD6, 0x5F, 255))
hr = R * 0.045                                         # spindle hole
d.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=(20, 20, 20, 255))

# highlight sweep across the disc
gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(gloss)
gd.polygon([(cx - R, cy - R * 0.55), (cx + R, cy - R), (cx + R, cy - R * 0.72),
            (cx - R, cy - R * 0.30)], fill=(255, 255, 255, 26))
disc_mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(disc_mask).ellipse([cx - R, cy - R, cx + R, cy + R], fill=255)
img.paste(Image.alpha_composite(img.crop((0, 0, S, S)), gloss), (0, 0), disc_mask)

here = os.path.dirname(os.path.abspath(__file__))
iconset = os.path.join(here, "AppIcon.iconset")
shutil.rmtree(iconset, ignore_errors=True)
os.makedirs(iconset)
for size in (16, 32, 64, 128, 256, 512):
    img.resize((size, size), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}.png")
    img.resize((size * 2, size * 2), Image.LANCZOS).save(f"{iconset}/icon_{size}x{size}@2x.png")
os.makedirs(os.path.join(here, "Resources"), exist_ok=True)
out = os.path.join(here, "Resources", "AppIcon.icns")
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)
shutil.rmtree(iconset, ignore_errors=True)
print("wrote", out)
