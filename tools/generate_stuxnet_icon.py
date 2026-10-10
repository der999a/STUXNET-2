from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parents[1]
targets = root / "Telegram" / "Telegram-iOS"

# An abstract local mark: a cyan circuit loop on graphite. It intentionally
# avoids Telegram's paper-plane silhouette while remaining legible at 20 px.
size = 1024
scale = 4
canvas = Image.new("RGBA", (size * scale, size * scale), (11, 20, 28, 255))
draw = ImageDraw.Draw(canvas)

def pts(values):
    return [(int(x * scale), int(y * scale)) for x, y in values]

center = (512 * scale, 512 * scale)
draw.rounded_rectangle((72 * scale, 72 * scale, 952 * scale, 952 * scale), radius=206 * scale, fill=(15, 34, 47, 255))
draw.rounded_rectangle((84 * scale, 84 * scale, 940 * scale, 940 * scale), radius=194 * scale, outline=(33, 77, 91, 255), width=10 * scale)

glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
loop = pts([(288, 326), (432, 238), (670, 276), (742, 428), (626, 548), (396, 600), (316, 724), (488, 794), (700, 708)])
glow_draw.line(loop, fill=(53, 218, 232, 210), width=42 * scale, joint="curve")
glow = glow.filter(ImageFilter.GaussianBlur(24 * scale))
canvas = Image.alpha_composite(canvas, glow)
draw = ImageDraw.Draw(canvas)
draw.line(loop, fill=(121, 242, 247, 255), width=22 * scale, joint="curve")

nodes = [(288, 326), (742, 428), (316, 724), (700, 708)]
for x, y in nodes:
    box = (int((x - 26) * scale), int((y - 26) * scale), int((x + 26) * scale), int((y + 26) * scale))
    draw.ellipse(box, fill=(11, 20, 28, 255), outline=(154, 255, 255, 255), width=11 * scale)
    inner = (int((x - 9) * scale), int((y - 9) * scale), int((x + 9) * scale), int((y + 9) * scale))
    draw.ellipse(inner, fill=(154, 255, 255, 255))

draw.rounded_rectangle((442 * scale, 408 * scale, 582 * scale, 616 * scale), radius=40 * scale, fill=(17, 49, 62, 235), outline=(188, 255, 255, 255), width=9 * scale)
draw.line(pts([(468, 462), (552, 462), (552, 514), (468, 514), (468, 568), (552, 568)]), fill=(188, 255, 255, 255), width=16 * scale, joint="curve")

base = canvas.resize((1024, 1024), Image.Resampling.LANCZOS)
appicon = targets / "AppIcons.xcassets" / "StuxnetIcon.appiconset"
alticon = targets / "StuxnetIcon.alticon"
appicon.mkdir(parents=True, exist_ok=True)
alticon.mkdir(parents=True, exist_ok=True)

app_sizes = {
    "Icon2@20x20.png": 20, "Icon2@29x29.png": 29, "Icon2@40x40.png": 40,
    "Icon2@40x40-1.png": 40, "Icon2@40x40-2.png": 40, "Icon2@58x58.png": 58,
    "Icon2@58x58-1.png": 58, "Icon2@60x60.png": 60, "Icon2@76x76.png": 76,
    "Icon2@80x80.png": 80, "Icon2@80x80-1.png": 80, "Icon2@87x87.png": 87,
    "Icon2@120x120.png": 120, "Icon2@120x120-1.png": 120, "Icon2@152x152.png": 152,
    "Icon2@167x167.png": 167, "Icon2@180x180.png": 180,
}
for name, px in app_sizes.items():
    base.resize((px, px), Image.Resampling.LANCZOS).save(appicon / name, "PNG", optimize=True)
for name, px in {
    "StuxnetIcon@2x.png": 120, "StuxnetIcon@3x.png": 180,
    "StuxnetIconIpad.png": 76, "StuxnetIconIpad@2x.png": 152,
    "StuxnetIconLargeIpad@2x.png": 167,
}.items():
    base.resize((px, px), Image.Resampling.LANCZOS).save(alticon / name, "PNG", optimize=True)
