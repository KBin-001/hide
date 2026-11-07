"""Draw the classic four-key calculator icon as opaque RGB PNGs."""
import json
import math
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1] / "Resources/Assets.xcassets"


def png(size):
    scale = 1024 / size

    def coverage(distance):
        return max(0, min(1, 0.5 - distance / scale))

    def blend(base, foreground, alpha):
        return tuple(round(a + (b - a) * alpha) for a, b in zip(base, foreground))

    def bar(x, y, half_width=79, half_height=11):
        return max(abs(x) - half_width, abs(y) - half_height)

    def glyph(x, y, right, bottom):
        if not bottom:
            return bar(x, y) if right else min(bar(x, y), bar(y, x))
        if right:
            return bar(x, abs(y) - 26)
        diagonal = math.sqrt(0.5)
        u, v = (x + y) * diagonal, (x - y) * diagonal
        return min(bar(u, v), bar(v, u))

    def pixel(x, y):
        x, y = (x + 0.5) * scale, (y + 0.5) * scale
        shade = round(62 * (1 - y / 1024) ** 0.9)
        color = (shade, shade, shade)
        right, bottom = x >= 512, y >= 512
        dx, dy = x - (732 if right else 292), y - (732 if bottom else 292)
        circle = coverage(math.hypot(dx, dy) - 186)
        if not circle:
            return bytes(color)
        if right and bottom:
            light = 1 - min(1, math.hypot(dx + 118, dy + 130) / 310)
            fill = blend((250, 100, 22), (255, 190, 22), light)
        else:
            light = 1 - min(1, math.hypot(dx + 88, dy + 106) / 352)
            gray = round(101 + 51 * light)
            fill = (gray, gray, gray)
        color = blend(color, fill, circle)
        shadow = coverage(glyph(dx, dy - 5, right, bottom)) * 0.20
        if shadow:
            color = blend(color, (0, 0, 0), shadow)
        mark = coverage(glyph(dx, dy, right, bottom))
        if mark:
            color = blend(color, (255, 255, 255), mark)
        return bytes(color)

    raw = b"".join(b"\0" + b"".join(pixel(x, y) for x in range(size)) for y in range(size))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    target = ROOT / "AppIcon.appiconset"
    target.mkdir(parents=True, exist_ok=True)
    images = []
    for points in (20, 29, 40, 60):
        for scale in (2, 3):
            size = points * scale
            name = f"icon-{size}.png"
            (target / name).write_bytes(png(size))
            images.append({"idiom": "iphone", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
    (target / "icon-1024.png").write_bytes(png(1024))
    images.append({"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"})
    (target / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")
    (ROOT / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n', encoding="utf-8")


if __name__ == "__main__":
    main()
