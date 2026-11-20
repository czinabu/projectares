"""Shrinks the Universal Base Characters textures in a folder, in place,
before `build_rig.tscn` packs them into the rig: the body's maps to 2048,
hair to 1024 (eyes are already small). Needs Pillow.

    python3 tools/human_rig/shrink_textures.py <folder>
"""
import pathlib
import sys

from PIL import Image

for path in pathlib.Path(sys.argv[1]).glob("T_*.png"):
    size = 1024 if "Hair" in path.name else 2048
    with Image.open(path) as image:
        if image.width <= size:
            continue
        small = image.resize((size, size * image.height // image.width), Image.LANCZOS)
    small.save(path, optimize=True)
    print(path.name, size)
