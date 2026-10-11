#!/usr/bin/env python3
"""Build README showcase images from actual deterministic Flutter golden screenshots.

Never synthesizes app UI: only crops/scales existing test-rendered screenshots.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "screenshots"
OUT = SOURCE / "showcase"
OUT.mkdir(parents=True, exist_ok=True)
NAVY = "#101b32"
PANEL = "#192a48"
WHITE = "#f2f7ff"
MUTED = "#a9bbd6"
BLUE = "#78b9ff"

def font(size, bold=False):
    paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for path in paths:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def cover(source, size):
    image = Image.open(SOURCE / source).convert("RGB")
    # Preserve complete screenshot, including all real UI pixels.
    image.thumbnail(size, Image.Resampling.LANCZOS)
    return image

def card(canvas, draw, source, x, y, w, h, label):
    draw.rounded_rectangle((x, y, x+w, y+h), radius=28, fill=PANEL)
    im = cover(source, (w-40, h-95))
    canvas.paste(im, (x+(w-im.width)//2, y+25))
    draw.text((x+28, y+h-57), label, fill=WHITE, font=font(23, True))

def banner():
    image = Image.new("RGB", (1440, 760), NAVY)
    d = ImageDraw.Draw(image)
    d.ellipse((1030, -240, 1630, 350), fill="#1b4168")
    d.ellipse((-300, 500, 330, 1100), fill="#203455")
    d.text((75, 74), "LOCAL BLUEY", font=font(25, True), fill=BLUE)
    d.text((75, 135), "A little companion.", font=font(60, True), fill=WHITE)
    d.text((75, 214), "A lot of possibilities.", font=font(46, True), fill=WHITE)
    d.text((78, 314), "Local-first AI assistance for your Mac", font=font(27), fill=MUTED)
    d.text((78, 359), "with iPhone and Android companions.", font=font(27), fill=MUTED)
    # Use the actual shipped cross-platform character icon, not the placeholder Flutter face.\n    icon = Image.open(ROOT / "assets/icons/bluey-mobile.png").convert("RGB")\n    icon.thumbnail((480, 480), Image.Resampling.LANCZOS)\n    image.paste(icon, (875, 120))\n    d.text((900, 628), "SHIPPED APP ICON", font=font(19, True), fill=MUTED)
    d.text((75, 681), "SHIPPED ICON ARTWORK  •  NOT AN IN-APP SCREENSHOT", font=font(17, True), fill=MUTED)
    image.save(OUT / "hero.png", optimize=True)

def gallery():
    image=Image.new("RGB",(1440,1040),NAVY)
    d=ImageDraw.Draw(image)
    d.text((62,48),"See Bluey in action",font=font(52,True),fill=WHITE)
    d.text((65,121),"Screens captured from the project's Flutter test harness",font=font(23),fill=MUTED)
    items=[\n        ("settings-default-dark.png","Settings · dark"),\n        ("onboarding-start-light.png","Onboarding"),\n        ("settings-default-light.png","Settings · light"),\n        ("onboarding-he-light.png","Hebrew · RTL"),\n    ]
    for i,(src,label) in enumerate(items):
        card(image,d,src,60+(i%2)*710,185+(i//2)*400,670,365,label)
    d.text((65,989),"FLUTTER TEST FIXTURES • NO REAL HARDWARE VALIDATION",font=font(16,True),fill=MUTED)
    image.save(OUT/"gallery.png",optimize=True)

if __name__=="__main__":
    banner()
    gallery()
    for f in sorted(OUT.glob("*.png")):
        print(f.relative_to(ROOT), f.stat().st_size, "bytes")
