from PIL import Image, ImageDraw, ImageFont, ImageFilter
import sys
out = sys.argv[1]
FONT = "assets/fonts/Rajdhani-SemiBold.ttf"
AMBER = (255, 158, 56)
BG = (14, 12, 18)

CYAN = (77, 217, 255)

def chamfer(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]

def emblem(size):
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # A hard-cornered plate, not a rounded app tile.
    d.polygon(chamfer(0, 0, s - 1, s - 1, s * 0.12), fill=BG + (255,))
    # The lane's gate frame, thin and cyan, broken at the corners like the
    # arches in the tunnel, with the short ticks inside them.
    m, bw, gap = s * 0.1, max(2, s // 56), s * 0.2
    x0, y0, x1, y1 = m, m, s - m, s - m
    for (ax, ay, bx, by) in [(x0 + gap, y0, x1 - gap, y0), (x0 + gap, y1, x1 - gap, y1),
                             (x0, y0 + gap, x0, y1 - gap), (x1, y0 + gap, x1, y1 - gap)]:
        d.rectangle([ax - bw / 2, ay - bw / 2, bx + bw / 2, by + bw / 2], fill=CYAN + (255,))
    tick = s * 0.1
    for sx, ex in [(x0, 1), (x1, -1)]:
        for sy, ey in [(y0, 1), (y1, -1)]:
            xa, xb = sorted([sx, sx + ex * tick])
            ya, yb = sorted([sy, sy + ey * tick])
            d.rectangle([xa, sy - bw / 2, xb, sy + bw / 2], fill=CYAN + (255,))
            d.rectangle([sx - bw / 2, ya, sx + bw / 2, yb], fill=CYAN + (255,))
    # The V: two heavy amber slabs meeting at the point, cut across by a
    # slit, so it reads as a line you cross: the verge.
    cx = s / 2
    top, base = s * 0.27, s * 0.76
    w = s * 0.26
    t = s * 0.115
    outer = [(cx - w, top), (cx - w + t * 1.25, top), (cx, base - t * 2.4), (cx + w - t * 1.25, top), (cx + w, top), (cx, base)]
    d.polygon(outer, fill=AMBER + (255,))
    slit = s * 0.015
    cut = top + (base - top) * 0.5
    d.polygon([(0, cut), (s, cut), (s, cut + slit * 2), (0, cut + slit * 2)], fill=BG + (255,))
    # Cyan spark under the point: the way out.
    d.polygon([(cx - s * 0.035, base + s * 0.03), (cx + s * 0.035, base + s * 0.03), (cx, base + s * 0.075)], fill=CYAN + (255,))
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
