"""Draws Earshot's logo and banner.

A speech bubble with a voice in it, and sound waves that fade with distance, on a dark
tile in Earshot's blue (the colour of its name in chat).

    python tools/make_logo.py

Writes media/logo.svg, media/logo.png (512 x 512, for CurseForge and GitHub),
media/banner.png (1280 x 640, for the top of the README and GitHub's social preview) and
Earshot/Media/Icon.tga (64 x 64, the icon in the game's addon list and minimap menu).
Needs rsvg-convert (from librsvg) and Pillow.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BLUE = "#8fd0ff"   # Earshot's name in chat
INK = "#1c1610"    # the speech bubble's outline, as on the who's-talking marker
PAPER = "#fcf6e4"  # the speech bubble
NAVY = "#17283b"


def defs(prefix):
    return f"""
  <defs>
    <radialGradient id="{prefix}bg" cx="0.40" cy="0.42" r="0.75">
      <stop offset="0" stop-color="#21405f"/>
      <stop offset="0.55" stop-color="#132438"/>
      <stop offset="1" stop-color="#09111b"/>
    </radialGradient>
    <linearGradient id="{prefix}rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#8db8dc"/>
      <stop offset="1" stop-color="#2a4762"/>
    </linearGradient>
    <linearGradient id="{prefix}paper" gradientUnits="userSpaceOnUse" x1="0" y1="150" x2="0" y2="382">
      <stop offset="0" stop-color="#fffbef"/>
      <stop offset="1" stop-color="#efe2c4"/>
    </linearGradient>
    <filter id="{prefix}glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="9"/>
    </filter>
    <filter id="{prefix}shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feGaussianBlur stdDeviation="7"/>
    </filter>
  </defs>"""


def arc(cx, cy, r, degrees):
    """An arc of radius r around (cx, cy), from -degrees to +degrees (0 = pointing right)."""
    import math
    a = math.radians(degrees)
    x1, y1 = cx + r * math.cos(-a), cy + r * math.sin(-a)
    x2, y2 = cx + r * math.cos(a), cy + r * math.sin(a)
    return f"M {x1:.1f} {y1:.1f} A {r} {r} 0 0 1 {x2:.1f} {y2:.1f}"


def glyph(prefix):
    """The speech bubble and its waves, on a 512 x 512 grid."""
    body = '<rect x="58" y="150" width="212" height="172" rx="72"/>'
    tail = '<path d="M 102 296 L 168 300 L 78 382 Z"/>'
    bars = ""
    for x, h in ((92, 44), (124, 96), (156, 122), (188, 80), (220, 44)):
        bars += f'<rect x="{x}" y="{236 - h / 2:.0f}" width="20" height="{h}" rx="10"/>'
    waves = [(74, 30, 1.0), (126, 28, 0.62), (178, 26, 0.3)]
    glow = "".join(
        f'<path d="{arc(262, 236, r, 42)}" stroke-width="{w + 8}" stroke-opacity="{o * 0.8:.2f}"/>'
        for r, w, o in waves)
    lines = "".join(
        f'<path d="{arc(262, 236, r, 42)}" stroke-width="{w}" stroke-opacity="{o:.2f}"/>' for r, w, o in waves)
    return f"""
  <g fill="#000" opacity="0.45" filter="url(#{prefix}shadow)" transform="translate(0 10)">{body}{tail}</g>
  <g fill="{INK}" stroke="{INK}" stroke-width="22" stroke-linejoin="round">{body}{tail}</g>
  <g fill="url(#{prefix}paper)">{body}{tail}</g>
  <g fill="{NAVY}">{bars}</g>
  <g fill="none" stroke="#bfe6ff" stroke-linecap="round" filter="url(#{prefix}glow)">{glow}</g>
  <g fill="none" stroke="{BLUE}" stroke-linecap="round">{lines}</g>"""


def logo_svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">{defs("l")}
  <rect x="14" y="14" width="484" height="484" rx="100" fill="url(#lbg)"/>
  <rect x="17" y="17" width="478" height="478" rx="97" fill="none" stroke="url(#lrim)" stroke-width="6"/>
  <rect x="26" y="26" width="460" height="460" rx="88" fill="none" stroke="#ffffff" stroke-opacity="0.06"
    stroke-width="2"/>{glyph("l")}
</svg>
"""


def banner_svg():
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640">{defs("b")}
  <rect width="1280" height="640" fill="#0e1926"/>
  <g transform="translate(96 130) scale(0.74)">
    <rect x="14" y="14" width="484" height="484" rx="100" fill="url(#bbg)"/>
    <rect x="17" y="17" width="478" height="478" rx="97" fill="none" stroke="url(#brim)" stroke-width="6"/>
    {glyph("b")}
  </g>
  <text x="560" y="300" font-family="Inter Display" font-weight="800" font-size="132" fill="#f4f8fc"
    letter-spacing="-2">Earshot</text>
  <text x="566" y="372" font-family="Inter" font-weight="500" font-size="38" fill="{BLUE}">NPC voices fade as you walk away</text>
  <text x="566" y="424" font-family="Inter" font-weight="400" font-size="28" fill="#9fb3c6">A companion for Spoken on WoW Forever</text>
</svg>
"""


def render(svg_text, out, width, height):
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(out), f.name], check=True)
    Path(f.name).unlink()


def main():
    media = ROOT / "media"
    media.mkdir(exist_ok=True)
    svg = logo_svg()
    (media / "logo.svg").write_text(svg)
    render(svg, media / "logo.png", 512, 512)
    render(banner_svg(), media / "banner.png", 1280, 640)
    with tempfile.TemporaryDirectory() as tmp:
        big = Path(tmp) / "icon.png"
        render(svg, big, 256, 256)
        Image.open(big).convert("RGBA").resize((64, 64), Image.LANCZOS).save(
            ROOT / "Earshot" / "Media" / "Icon.tga", format="TGA")
    print("Wrote media/logo.svg, media/logo.png, media/banner.png and Earshot/Media/Icon.tga")


if __name__ == "__main__":
    sys.exit(main())
