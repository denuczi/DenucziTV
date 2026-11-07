#!/usr/bin/env python3
"""Build native and Flutter icons from the approved DenucziTV artwork.

Development-only dependency: Pillow (`python3 -m pip install Pillow`).
Never extract the mark with color thresholds, crop it, or round corners twice.
The approved original, including its symbol and white badge, is kept intact.
Only its black *exterior corner matte* is made transparent to prevent black
corners on the OS dock/taskbar. The interior geometric artwork is untouched.

All sizes and the Windows .ico derive from the same master bitmap.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets' / 'branding'
ORIGINAL = ASSETS / 'source' / 'approved_app_icon.png'
SIZES = (16, 24, 32, 48, 64, 128, 256, 512, 1024)


def prepare_master():
    image = Image.open(ORIGINAL).convert('RGBA')
    if image.width != image.height:
        raise ValueError('Approved artwork must have square dimensions')
    # The source image already has a white rounded badge. The black outside
    # the four corners was introduced by the renderer. Make only that outer
    # corner matte transparent. No alpha threshold touches the dark D itself.
    n = image.width
    limit = round(n * 0.21)
    pixels = image.load()
    for y in list(range(limit)) + list(range(n - limit, n)):
        for x in list(range(limit)) + list(range(n - limit, n)):
            r, g, b, old_alpha = pixels[x, y]
            brightness = (r + g + b) / 3
            alpha = round(max(0.0, min(1.0, (brightness - 8.0) / 228.0)) * old_alpha)
            if alpha < 254:
                pixels[x, y] = (248, 249, 252, alpha)
    return image


def build():
    master = prepare_master()
    for size in SIZES:
        output = master.resize((size, size), Image.Resampling.LANCZOS)
        output.save(ASSETS / f'icon_{size}.png', optimize=True)
    # Single canonical PNG is used by Flutter and the native Linux runner.
    master.resize((1024, 1024), Image.Resampling.LANCZOS).save(
        ASSETS / 'denuczitv_app_icon.png', optimize=True,
    )
    # Windows .ico bundles 7 frames generated from this very same source.
    master.resize((256, 256), Image.Resampling.LANCZOS).save(
        ASSETS / 'denuczitv.ico', format='ICO',
        sizes=[(n, n) for n in SIZES if n <= 256],
    )
    print('Built a single synchronized DenucziTV icon family')


if __name__ == '__main__':
    build()
