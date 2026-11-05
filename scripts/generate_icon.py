"""Original calculator icon; RGB PNGs generated with the Python standard library."""
import json
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1] / "Resources/Assets.xcassets"


def png(size):
    def pixel(x, y):
        x, y = x / size * 1024, y / size * 1024
        color = (25, 29, 38)
        if 180 <= x < 844 and 170 <= y < 362:
            color = (56, 67, 78)
        if 560 <= x < 770 and 245 <= y < 269:
            color = (218, 233, 224)
        for row in range(3):
            for col in range(3):
                left, top = 180 + col * 244, 430 + row * 158
                if left <= x < left + 176 and top <= y < top + 110:
                    color = (244, 157, 46) if col == 2 else (74, 81, 94)
        if 714 <= x < 746 and 455 <= y < 515 or 700 <= x < 760 and 482 <= y < 490:
            color = (255, 255, 255)
        if 700 <= x < 760 and (638 <= y < 646 or 670 <= y < 678):
            color = (255, 255, 255)
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
