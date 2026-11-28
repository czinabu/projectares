from PIL import Image, ImageDraw, ImageFont, ImageFilter
import sys
out = sys.argv[1]
FONT = "assets/fonts/Rajdhani-SemiBold.ttf"
AMBER = (255, 158, 56)
BG = (14, 12, 18)

def emblem(size):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = s * 0.2
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=BG + (255,), outline=(60, 52, 48, 255), width=max(1, s // 64))
    # A spearhead "V": an outer chevron pointing down, a lit core.
    cx = s / 2
    top, base = s * 0.2, s * 0.82
    w = s * 0.34
    t = s * 0.11
    outer = [(cx - w, top), (cx - w + t * 1.15, top), (cx, base - t * 2.3), (cx + w - t * 1.15, top), (cx + w, top), (cx, base)]
    d.polygon(outer, fill=AMBER + (255,))
    # a cyan spark at the tip, the lane's colour
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - s * 0.05, base - s * 0.05 - t * 0.6, cx + s * 0.05, base + s * 0.05 - t * 0.6], fill=(150, 240, 255, 230))
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.02))
    img = Image.alpha_composite(img, glow)
    return img.resize((size, size), Image.LANCZOS)

icon = emblem(512)
icon.save(f"{out}/icon.png")
emblem(256).save(f"{out}/icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
# Boot splash: the emblem over the name, on the start screen's dark.
W, H = 1600, 900
splash = Image.new("RGBA", (W, H), (9, 8, 11, 255))
e = emblem(260)
splash.alpha_composite(e, ((W - 260) // 2, 230))
d = ImageDraw.Draw(splash)
f = ImageFont.truetype(FONT, 64)
text = "V E R G E"
tw = d.textlength(text, font=f)
d.text(((W - tw) / 2, 540), text, font=f, fill=(240, 237, 230, 255))
d.rectangle([W / 2 - 36, 630, W / 2 + 36, 633], fill=AMBER + (255,))
splash.convert("RGB").save(f"{out}/splash.png")
