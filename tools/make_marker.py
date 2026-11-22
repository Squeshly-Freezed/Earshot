"""Makes the who's-talking marker: a speech bubble with three dots (64x64 TGA)."""
import sys

from PIL import Image, ImageDraw

BIG, SIZE = 256, 64
INK = (28, 22, 16, 255)        # outline and dots
PAPER = (252, 246, 228, 255)   # the bubble


def bubble(d, inset, colour):
    """The bubble's body and tail, shrunk by `inset` pixels on every side."""
    d.rounded_rectangle((20 + inset, 28 + inset, 236 - inset, 182 - inset), radius=58 - inset, fill=colour)
    d.polygon([(70 + inset, 160), (128 - inset, 160), (56 + inset * 1.6, 232 - inset * 2.2)], fill=colour)


def main(path):
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bubble(d, 0, INK)     # the outline is the bubble drawn dark...
    bubble(d, 12, PAPER)  # ...with a smaller light one on top
    for x in (84, 128, 172):
        d.ellipse((x - 15, 90, x + 15, 120), fill=INK)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path, format="TGA")


if __name__ == "__main__":
    main(sys.argv[1])
