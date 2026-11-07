#!/usr/bin/env python3
"""Draws Resources/AppIcon.png (1024x1024): a window snapped to the left half, on a blue→indigo squircle.
build.sh turns it into AppIcon.icns on the Mac. Re-run only to change the design (needs Pillow)."""
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
K = 2                     # supersampling factor
W = S * K


def px(v):
    return int(v * K)


def rounded_mask(box, radius):
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).rounded_rectangle([px(c) for c in box], radius=px(radius), fill=255)
    return m


# --- background squircle (Apple grid: 824 px body with ~100 px margin) --------------------------------
body = (100, 100, 924, 924)
base = Image.new("RGBA", (W, W), (0, 0, 0, 0))

shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 90), mask=rounded_mask((body[0], body[1] + 14, body[2], body[3] + 14), 185))
base = Image.alpha_composite(base, shadow.filter(ImageFilter.GaussianBlur(px(18))))

top, bottom = (79, 140, 255), (98, 64, 245)
grad = Image.composite(Image.new("RGB", (W, W), bottom), Image.new("RGB", (W, W), top),
                       Image.linear_gradient("L").resize((W, W)))
bg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bg.paste(grad, mask=rounded_mask(body, 185))
base = Image.alpha_composite(base, bg)

# soft highlight: fades smoothly from the top edge, no visible band
fade = Image.linear_gradient("L").transpose(Image.FLIP_TOP_BOTTOM).resize((W, px(560)))
fade_full = Image.new("L", (W, W), 0)
fade_full.paste(fade, (0, px(100)))
alpha = ImageChops.multiply(fade_full.point(lambda v: v * 48 // 255), rounded_mask(body, 185))
hl = Image.new("RGBA", (W, W), (255, 255, 255, 0))
hl.putalpha(alpha)
base = Image.alpha_composite(base, hl)

# --- glyph: a window, left half snapped ----------------------------------------------------------------
d = ImageDraw.Draw(base)
win = (232, 292, 792, 732)           # 560 x 440
line = 30
mid = (win[0] + win[2]) // 2

# right half: faint pane
pane = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(pane).rounded_rectangle([px(c) for c in (mid, win[1], win[2], win[3])], radius=px(44),
                                       fill=(255, 255, 255, 70))
cut = Image.new("L", (W, W), 0)
ImageDraw.Draw(cut).rectangle([px(mid), 0, W, W], fill=255)
pane.putalpha(Image.composite(pane.getchannel("A"), Image.new("L", (W, W), 0), cut))
base = Image.alpha_composite(base, pane)

# left half: solid snapped pane
snap = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(snap).rounded_rectangle([px(c) for c in (win[0], win[1], win[2], win[3])], radius=px(44),
                                       fill=(255, 255, 255, 255))
cut2 = Image.new("L", (W, W), 0)
ImageDraw.Draw(cut2).rectangle([0, 0, px(mid), W], fill=255)
snap.putalpha(Image.composite(snap.getchannel("A"), Image.new("L", (W, W), 0), cut2))
base = Image.alpha_composite(base, snap)

# window outline + title bar divider
d = ImageDraw.Draw(base)
d.rounded_rectangle([px(c) for c in win], radius=px(44), outline=(255, 255, 255, 255), width=px(line))
d.rectangle([px(win[0] + line / 2), px(win[1] + 92), px(win[2] - line / 2), px(win[1] + 92 + 18)], fill=(255, 255, 255, 255))
d.rectangle([px(mid - 9), px(win[1] + 92), px(mid + 9), px(win[3] - line / 2)], fill=(255, 255, 255, 255))
for i in range(3):                    # traffic-light dots in the title bar
    cx = win[0] + 62 + i * 52
    cy = win[1] + 46
    d.ellipse([px(cx - 14), px(cy - 14), px(cx + 14), px(cy + 14)], fill=(98, 100, 245, 255))

base = base.resize((S, S), Image.LANCZOS)
base.save("Resources/AppIcon.png")
print("wrote Resources/AppIcon.png", base.size)
