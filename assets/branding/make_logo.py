"""Draws the game's icon and boot splash: python3 assets/branding/make_logo.py assets/branding
Run from the project root (it reads the game's font). Palette: void #0E0C12,
cyan #4DD9FF (powered things), amber #FF9E38 (the mark), steel greys."""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
AMBER=(255,158,56); AMBER_HI=(255,196,110); AMBER_LO=(196,104,28); BG=(14,12,18); CYAN=(77,217,255); STEEL=(98,92,104); DARK=(30,28,36); GLASS=(6,18,26)
S=2048; CK=0.34; R=S*0.4; LINE=int(S*0.012); HEAVY=int(S*0.03)
def octa(r,c=None,cx=S/2,cy=S/2):
    c=r*CK if c is None else c
    return [(cx-r+c,cy-r),(cx+r-c,cy-r),(cx+r,cy-r+c),(cx+r,cy+r-c),(cx+r-c,cy+r),(cx-r+c,cy+r),(cx-r,cy+r-c),(cx-r,cy-r+c)]
def plate():
    img=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(img); c=S*0.12
    pts=lambda i:[(i+c,i),(S-i-c,i),(S-i,i+c),(S-i,S-i-c),(S-i-c,S-i),(i+c,S-i),(i,S-i-c),(i,i+c)]
    d.polygon(pts(0),fill=(52,46,44,255)); d.polygon(pts(S*0.012),fill=BG+(255,))
    return img
def outline(img,pts,col,w):
    ov=Image.new("RGBA",img.size,(0,0,0,0)); ImageDraw.Draw(ov).line(pts+[pts[0],pts[1]],fill=col,width=w,joint="curve")
    img.alpha_composite(ov)
def vee_pts(cx,top,base,w,t): return [(cx-w,top),(cx-w+t*1.25,top),(cx,base-t*2.4),(cx+w-t*1.25,top),(cx+w,top),(cx,base)]
# the one V every logo shares: same size, place and lighting
VT,VB,VW,VK=S*0.35,S*0.65,S*0.14,S*0.065
def mark(img,top=VT,base=VB,col=None,w=VW,t=VK):
    d=ImageDraw.Draw(img); cx=S/2
    if col: d.polygon(vee_pts(cx,top,base,w,t),fill=col); return
    d.polygon([(cx-w,top),(cx-w+t*1.25,top),(cx,base-t*2.4),(cx,base)],fill=AMBER_HI)
    d.polygon([(cx+w,top),(cx+w-t*1.25,top),(cx,base-t*2.4),(cx,base)],fill=AMBER_LO)
def B():
    Rb=R*0.74
    img=plate(); d=ImageDraw.Draw(img); cy=S/2; cx=S/2
    # strap: panelled links with a lit seam each side, joined to the case by angled lugs
    for sx in (-1,1):
        x_in=cx+sx*(Rb+S*0.02); x_out=cx+sx*S*0.5
        d.rectangle([min(x_in,x_out),cy-S*0.185,max(x_in,x_out),cy+S*0.185],fill=DARK)
        for off in (-S*0.185,S*0.185-LINE): d.rectangle([min(x_in,x_out),cy+off,max(x_in,x_out),cy+off+LINE],fill=CYAN+(170,))
        for j in range(1,6):
            xx=x_in+sx*(j*S*0.028); d.rectangle([xx-LINE//2,cy-S*0.185,xx+LINE//2,cy+S*0.185],fill=(52,48,58))
        d.polygon([(cx+sx*(Rb-S*0.01),cy-S*0.205),(cx+sx*(Rb+S*0.05),cy-S*0.185),(cx+sx*(Rb+S*0.05),cy+S*0.185),(cx+sx*(Rb-S*0.01),cy+S*0.205)],fill=STEEL)
    for sx in (-1,1): d.rectangle([min(cx+sx*(Rb+S*0.06),cx+sx*S*0.5),cy-S*0.012,max(cx+sx*(Rb+S*0.06),cx+sx*S*0.5),cy+S*0.012],fill=CYAN+(210,))
    # case: steel octagon with a darker inner bezel, cyan notches round it and two side buttons
    d.polygon(octa(Rb+S*0.03),fill=STEEL); d.polygon(octa(Rb+S*0.005),fill=(66,61,72)); d.polygon(octa(Rb-S*0.018),fill=STEEL)
    d.polygon(octa(Rb-S*0.04),fill=GLASS)
    for (x,y,h) in [(cx-S*0.16,cy-Rb-S*0.015,1),(cx,cy-Rb-S*0.015,1),(cx+S*0.16,cy-Rb-S*0.015,1),(cx-S*0.16,cy+Rb+S*0.015,1),(cx,cy+Rb+S*0.015,1),(cx+S*0.16,cy+Rb+S*0.015,1)]:
        d.rectangle([x-S*0.025,y-S*0.006,x+S*0.025,y+S*0.006],fill=CYAN)
    for dy in (-S*0.12,S*0.05): d.rectangle([cx+Rb+S*0.03,cy+dy,cx+Rb+S*0.06,cy+dy+S*0.07],fill=STEEL)
    # screen layout, all on one grid centred on the V: brackets at the glass corners,
    # signal and battery in the top row, readout cells centred under the V
    g=Rb-S*0.075
    k=S*0.055; e=0.9
    for sx in (-1,1):
        for sy in (-1,1):
            px,py=cx+sx*g*e,cy+sy*g*e
            d.rectangle([min(px,px-sx*k),py-LINE//2,max(px,px-sx*k),py+LINE//2],fill=CYAN+(200,))
            d.rectangle([px-LINE//2,min(py,py-sy*k),px+LINE//2,max(py,py-sy*k)],fill=CYAN+(200,))
    # one signal icon centred above the V and three readout cells centred below it
    ty=cy-S*0.2
    for j in range(4): d.rectangle([cx-S*0.03+j*S*0.017,ty+S*0.03-j*S*0.009,cx-S*0.03+j*S*0.017+S*0.009,ty+S*0.04],fill=CYAN+(110+j*40,))
    by_=cy+S*0.17
    for j in range(-1,2): d.rectangle([cx+j*S*0.06-S*0.022,by_,cx+j*S*0.06+S*0.022,by_+S*0.016],fill=AMBER if j==0 else CYAN+(120,))
    mark(img,top=S*0.385,base=S*0.615,col=CYAN+(255,),w=S*0.1,t=S*0.045); return img

def emblem(size):
    return B().resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    import sys
    out = sys.argv[1]
    emblem(512).save(f"{out}/icon.png")
    emblem(256).save(f"{out}/icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # Boot splash: the emblem over the name, on the start screen's dark.
    W, H = 1600, 900
    splash = Image.new("RGBA", (W, H), (9, 8, 11, 255))
    e = emblem(300)
    splash.alpha_composite(e, ((W - 300) // 2, 200))
    d = ImageDraw.Draw(splash)
    f = ImageFont.truetype("assets/fonts/Oxanium.ttf", 64)
    f.set_variation_by_axes([600])
    text = "V E R G E"
    tw = d.textlength(text, font=f)
    d.text(((W - tw) / 2, 540), text, font=f, fill=(240, 237, 230, 255))
    splash.convert("RGB").save(f"{out}/splash.png")
