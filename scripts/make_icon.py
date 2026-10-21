"""Draws Resources/AppIcon.png (1024x1024): a macOS-style rounded square with a treemap inside."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # supersampling for smooth edges
S = SIZE * SCALE


def squircle_mask(box, radius):
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def vertical_gradient(top, bottom):
    gradient = Image.new("RGB", (1, S))
    for y in range(S):
        t = y / (S - 1)
        gradient.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return gradient.resize((S, S))


def lighten(color, amount):
    return tuple(int(c + (255 - c) * amount) for c in color)


def darken(color, amount):
    return tuple(int(c * (1 - amount)) for c in color)


def tile(canvas, box, color, radius):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    block = Image.new("RGB", (w, h))
    top, bottom = lighten(color, 0.28), darken(color, 0.22)
    draw = ImageDraw.Draw(block)
    for y in range(h):
        t = y / max(1, h - 1)
        draw.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=255)
    canvas.paste(block, (x0, y0), mask)
    # Glossy top edge.
    gloss = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gloss).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, outline=90, width=2 * SCALE)
    gloss_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gloss_mask).rectangle((0, 0, w, h // 2), fill=255)
    gloss = Image.composite(gloss, Image.new("L", (w, h), 0), gloss_mask)
    canvas.paste(Image.new("RGB", (w, h), (255, 255, 255)), (x0, y0), gloss)


def main():
    out = Path(__file__).resolve().parent.parent / "Resources" / "AppIcon.png"
    margin = 100 * SCALE
    box = (margin, margin, S - margin, S - margin)
    radius = 185 * SCALE

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (box[0], box[1] + 18 * SCALE, box[2], box[3] + 18 * SCALE), radius=radius, fill=(0, 0, 0, 120)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * SCALE))
    icon.alpha_composite(shadow)

    background = vertical_gradient((40, 46, 64), (14, 16, 24))
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(background, (0, 0), squircle_mask(box, radius))

    canvas = Image.new("RGB", (S, S), (0, 0, 0))
    canvas.paste(background, (0, 0))
    gap = 14 * SCALE
    inner = (box[0] + 74 * SCALE, box[1] + 74 * SCALE, box[2] - 74 * SCALE, box[3] - 74 * SCALE)
    ix0, iy0, ix1, iy1 = inner
    w, h = ix1 - ix0, iy1 - iy0
    r = 30 * SCALE
    violet, blue, green, orange, pink, yellow, cyan = (
        (150, 104, 247), (66, 140, 247), (48, 181, 133), (247, 150, 56), (240, 94, 143), (237, 196, 66), (46, 189, 207),
    )
    col = int(w * 0.56)
    tile(canvas, (ix0, iy0, ix0 + col - gap // 2, iy0 + int(h * 0.62) - gap // 2), violet, r)
    tile(canvas, (ix0, iy0 + int(h * 0.62) + gap // 2, ix0 + int(col * 0.55) - gap // 2, iy1), green, r)
    tile(canvas, (ix0 + int(col * 0.55) + gap // 2, iy0 + int(h * 0.62) + gap // 2, ix0 + col - gap // 2, iy1), pink, r)
    rx0 = ix0 + col + gap // 2
    tile(canvas, (rx0, iy0, ix1, iy0 + int(h * 0.40) - gap // 2), blue, r)
    tile(canvas, (rx0, iy0 + int(h * 0.40) + gap // 2, ix1, iy0 + int(h * 0.68) - gap // 2), orange, r)
    split = rx0 + int((ix1 - rx0) * 0.58)
    tile(canvas, (rx0, iy0 + int(h * 0.68) + gap // 2, split - gap // 2, iy1), yellow, r)
    tile(canvas, (split + gap // 2, iy0 + int(h * 0.68) + gap // 2, ix1, iy0 + int(h * 0.84) - gap // 4), cyan, r // 2)
    tile(canvas, (split + gap // 2, iy0 + int(h * 0.84) + gap // 4, ix1, iy1), (128, 138, 160), r // 2)

    body.paste(canvas, (0, 0), squircle_mask(box, radius))

    # Subtle top sheen and rim.
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 46), width=3 * SCALE)
    body.alpha_composite(sheen)

    icon.alpha_composite(body)
    icon.resize((SIZE, SIZE), Image.LANCZOS).save(out)
    print(f"saved {out}")


if __name__ == "__main__":
    main()
