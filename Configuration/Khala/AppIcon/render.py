"""Re-render the committed Khala icon PNGs from the two SVGs beside this file.

Needs cairosvg + Pillow (a throwaway venv is enough); CI never runs this, it only
copies the committed PNGs. Run: python3 render.py
"""
from io import BytesIO
from pathlib import Path

import cairosvg
from PIL import Image

HERE = Path(__file__).resolve().parent


def render(svg, size):
    png = cairosvg.svg2png(url=str(HERE / svg), output_width=size, output_height=size)
    return Image.open(BytesIO(png))


# App Store rejects a large app icon with an alpha channel (ITMS-90717), so the
# appiconset image is flattened to RGB. The Icon Composer layer keeps its alpha.
render("khala-icon.svg", 1024).convert("RGB").save(HERE / "AppIcon.appiconset/khala-1024.png", optimize=True)
render("khala-mark.svg", 1024).save(HERE / "AppIcon.icon/Assets/khala-mark.png", optimize=True)
