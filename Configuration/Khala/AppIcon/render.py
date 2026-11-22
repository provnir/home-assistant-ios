"""Re-render the committed Khala icon PNGs and in-app logo PDFs from the SVGs beside this file.

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

# In-app logos: Home Assistant's logomark replaced in place, so no Swift code changes and nothing for an
# upstream merge to trip on. The loading SVG is copied as is (WebKit plays its CSS animation).
ROOT = HERE.parents[2]
LOGOS = {
    "khala-logo.svg": [
        "Sources/Shared/Assets/SharedAssets.xcassets/Logo.imageset/khala-logo.pdf",
        "Sources/App/Resources/Assets.xcassets/LaunchScreen/launchScreen-logo.imageset/khala-logo.pdf",
    ],
    "khala-logo-circle.svg": ["Sources/App/Resources/Assets.xcassets/logo-in-circle.imageset/khala-logo-circle.pdf"],
}
for svg, targets in LOGOS.items():
    for target in targets:
        cairosvg.svg2pdf(url=str(HERE / svg), write_to=str(ROOT / target))
(ROOT / "Sources/App/Resources/home-assistant-logo-loading.svg").write_text((HERE / "khala-logo-loading.svg").read_text())
