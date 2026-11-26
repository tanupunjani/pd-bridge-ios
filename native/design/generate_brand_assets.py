"""Render the checked-in original bridge geometry into iOS icon rasters.

Requires Pillow only at asset-generation time. It is not an app dependency.
"""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SCALE = 4


def curve(p0, p1, p2, p3, steps=80):
    points = []
    for index in range(steps + 1):
        t = index / steps
        other = 1 - t
        points.append((
            other**3 * p0[0] + 3 * other**2 * t * p1[0] + 3 * other * t**2 * p2[0] + t**3 * p3[0],
            other**3 * p0[1] + 3 * other**2 * t * p1[1] + 3 * other * t**2 * p2[1] + t**3 * p3[1],
        ))
    return points


def arches(draw, outer, inner):
    first = curve((102, 717), (236, 276), (563, 276), (748, 717))
    first += [(584, 717)]
    first += curve((584, 717), (502, 502), (358, 502), (266, 717))
    second = curve((440, 717), (563, 379), (788, 379), (922, 717))
    second += [(768, 717)]
    second += curve((768, 717), (696, 553), (625, 553), (584, 717))
    draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in first], fill=outer)
    draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in second], fill=inner)


def render(background, outer, inner, path):
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE), background)
    arches(ImageDraw.Draw(image), outer, inner)
    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(path)


app = ROOT / "ios/App/Assets.xcassets"
render("#124C47", "#FFFFFF", "#9EDBC5", app / "AppIcon.appiconset/AppIcon.png")
render((0, 0, 0, 0), "#124C47", "#26786D", app / "BrandMark.imageset/BrandMark.png")
render("#124C47", "#FFFFFF", "#9EDBC5",
       ROOT / "watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
launch = Image.open(app / "BrandMark.imageset/BrandMark.png")
for scale in (1, 2, 3):
    launch.resize((180 * scale, 180 * scale), Image.Resampling.LANCZOS).save(
        app / f"LaunchMark.imageset/LaunchMark@{scale}x.png")
