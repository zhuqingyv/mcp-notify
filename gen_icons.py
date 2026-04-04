#!/usr/bin/env python3
"""
Generate 128x128 PNG icons for AI platforms.
Downloads real logos from official sources; falls back to pixel text if download fails.
Uses sips (macOS built-in) or PIL for image processing.
"""

import struct
import zlib
import os
import sys
import subprocess
import tempfile
import urllib.request
import urllib.error
import ssl

ICONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
os.makedirs(ICONS_DIR, exist_ok=True)

SIZE = 128
RADIUS = 24

# (filename, bg_hex, label, logo_urls)
# logo_urls: list of URLs to try in order; first success wins
ICONS = [
    ("claude",       "#D97757", "C",  [
        "https://claude.ai/favicon.ico",
        "https://www.anthropic.com/favicon.ico",
    ]),
    ("openai",       "#10A37F", "AI", [
        "https://openai.com/favicon.ico",
    ]),
    ("gemini",       "#8AB4F8", "G",  [
        "https://www.google.com/favicon.ico",
    ]),
    ("deepseek",     "#4D6BFE", "DS", [
        "https://www.deepseek.com/favicon.ico",
    ]),
    ("kimi",         "#000000", "K",  [
        "https://kimi.moonshot.cn/favicon.ico",
    ]),
    ("qwen",         "#6E6EFF", "Q",  [
        "https://tongyi.aliyun.com/favicon.ico",
    ]),
    ("doubao",       "#1D7DFA", "豆", [
        "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/bytedance.svg",
        "https://www.doubao.com/favicon.png",
    ]),
    ("coze",         "#1D7DFA", "Cz", [
        "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/coze.svg",
        "https://www.coze.cn/favicon.ico",
        "https://www.coze.com/favicon.ico",
    ]),
    ("copilot",      "#0078D4", "Co", [
        "https://copilot.microsoft.com/favicon.ico",
        "https://www.microsoft.com/favicon.ico",
    ]),
    ("cursor",       "#000000", "Cu", [
        "https://www.cursor.com/favicon.ico",
        "https://cursor.sh/favicon.ico",
    ]),
    ("grok",         "#000000", "X",  [
        "https://grok.com/favicon.ico",
        "https://x.com/favicon.ico",
    ]),
    ("perplexity",   "#20808D", "Px", [
        "https://www.perplexity.ai/favicon.ico",
    ]),
    ("zhipu",        "#3B82F6", "智", [
        "https://open.bigmodel.cn/favicon.ico",
        "https://www.zhipuai.cn/favicon.ico",
    ]),
    ("ernie-bot",    "#3388FF", "文", [
        "https://cdn.simpleicons.org/baidu",
        "https://qianfan.cloud.baidu.com/favicon.ico",
    ]),
    ("xunfei-spark", "#0052D9", "讯", [
        "https://xinghuo.xfyun.cn/favicon.ico",
        "https://www.xfyun.cn/favicon.ico",
    ]),
]


# ── Fallback: pure-Python pixel icon ─────────────────────────────────────────

def hex_to_rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def write_png(path, pixels):
    def chunk(name, data):
        c = struct.pack(">I", len(data)) + name + data
        return c + struct.pack(">I", zlib.crc32(name + data) & 0xFFFFFFFF)

    raw = b""
    for row in pixels:
        raw += b"\x00"
        for r, g, b, a in row:
            raw += bytes([r, g, b, a])

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    idat_data = zlib.compress(raw, 9)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", idat_data)
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)


def rounded_rect_mask(size, radius):
    mask = [[False] * size for _ in range(size)]
    r = radius
    for y in range(size):
        for x in range(size):
            in_rect = True
            if x < r and y < r:
                in_rect = (x - r) ** 2 + (y - r) ** 2 <= r * r
            elif x > size - 1 - r and y < r:
                in_rect = (x - (size - 1 - r)) ** 2 + (y - r) ** 2 <= r * r
            elif x < r and y > size - 1 - r:
                in_rect = (x - r) ** 2 + (y - (size - 1 - r)) ** 2 <= r * r
            elif x > size - 1 - r and y > size - 1 - r:
                in_rect = (x - (size - 1 - r)) ** 2 + (y - (size - 1 - r)) ** 2 <= r * r
            mask[y][x] = in_rect
    return mask


def draw_text_pixels(pixels, text):
    FONT = {
        'A': [0x0E,0x11,0x11,0x1F,0x11,0x11,0x11],
        'B': [0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E],
        'C': [0x0E,0x11,0x10,0x10,0x10,0x11,0x0E],
        'D': [0x1E,0x11,0x11,0x11,0x11,0x11,0x1E],
        'E': [0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F],
        'F': [0x1F,0x10,0x10,0x1E,0x10,0x10,0x10],
        'G': [0x0E,0x11,0x10,0x17,0x11,0x11,0x0E],
        'H': [0x11,0x11,0x11,0x1F,0x11,0x11,0x11],
        'I': [0x0E,0x04,0x04,0x04,0x04,0x04,0x0E],
        'J': [0x07,0x02,0x02,0x02,0x02,0x12,0x0C],
        'K': [0x11,0x12,0x14,0x18,0x14,0x12,0x11],
        'L': [0x10,0x10,0x10,0x10,0x10,0x10,0x1F],
        'M': [0x11,0x1B,0x15,0x11,0x11,0x11,0x11],
        'N': [0x11,0x19,0x15,0x13,0x11,0x11,0x11],
        'O': [0x0E,0x11,0x11,0x11,0x11,0x11,0x0E],
        'P': [0x1E,0x11,0x11,0x1E,0x10,0x10,0x10],
        'Q': [0x0E,0x11,0x11,0x11,0x15,0x12,0x0D],
        'R': [0x1E,0x11,0x11,0x1E,0x14,0x12,0x11],
        'S': [0x0E,0x11,0x10,0x0E,0x01,0x11,0x0E],
        'T': [0x1F,0x04,0x04,0x04,0x04,0x04,0x04],
        'U': [0x11,0x11,0x11,0x11,0x11,0x11,0x0E],
        'V': [0x11,0x11,0x11,0x11,0x11,0x0A,0x04],
        'W': [0x11,0x11,0x11,0x15,0x15,0x1B,0x11],
        'X': [0x11,0x11,0x0A,0x04,0x0A,0x11,0x11],
        'Y': [0x11,0x11,0x0A,0x04,0x04,0x04,0x04],
        'Z': [0x1F,0x01,0x02,0x04,0x08,0x10,0x1F],
        '0': [0x0E,0x11,0x13,0x15,0x19,0x11,0x0E],
        '1': [0x04,0x0C,0x04,0x04,0x04,0x04,0x0E],
        '2': [0x0E,0x11,0x01,0x06,0x08,0x10,0x1F],
        '3': [0x1F,0x01,0x02,0x06,0x01,0x11,0x0E],
        '4': [0x02,0x06,0x0A,0x12,0x1F,0x02,0x02],
        '5': [0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E],
        '6': [0x06,0x08,0x10,0x1E,0x11,0x11,0x0E],
        '7': [0x1F,0x01,0x02,0x04,0x08,0x08,0x08],
        '8': [0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E],
        '9': [0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C],
        '&': [0x0C,0x12,0x12,0x0C,0x15,0x12,0x0D],
        '-': [0x00,0x00,0x00,0x1F,0x00,0x00,0x00],
        ' ': [0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    }

    def get_glyph(ch):
        if ch in FONT:
            return FONT[ch]
        return [0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F]

    CHAR_W = 5
    CHAR_H = 7
    SCALE = 5
    GAP = SCALE

    chars = list(text.upper())
    total_w = len(chars) * CHAR_W * SCALE + (len(chars) - 1) * GAP
    total_h = CHAR_H * SCALE
    start_x = (SIZE - total_w) // 2
    start_y = (SIZE - total_h) // 2

    for ci, ch in enumerate(chars):
        glyph = get_glyph(ch)
        cx = start_x + ci * (CHAR_W * SCALE + GAP)
        for row_idx, row_bits in enumerate(glyph):
            for col_idx in range(CHAR_W):
                bit = (row_bits >> (CHAR_W - 1 - col_idx)) & 1
                if bit:
                    for dy in range(SCALE):
                        for dx in range(SCALE):
                            py = start_y + row_idx * SCALE + dy
                            px = cx + col_idx * SCALE + dx
                            if 0 <= py < SIZE and 0 <= px < SIZE:
                                pixels[py][px] = (255, 255, 255, 255)


def make_fallback_icon(name, bg_hex, label):
    bg = hex_to_rgb(bg_hex)
    mask = rounded_rect_mask(SIZE, RADIUS)
    pixels = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            if mask[y][x]:
                pixels[y][x] = (bg[0], bg[1], bg[2], 255)
    draw_text_pixels(pixels, label)
    path = os.path.join(ICONS_DIR, name + ".png")
    write_png(path, pixels)
    return path


# ── Download + resize via sips ────────────────────────────────────────────────

def extract_largest_from_ico(ico_path):
    """
    Extract the largest image from an ICO file.
    Returns path to a temp PNG/BMP file, or None on failure.
    ICO format: 6-byte header + N * 16-byte directory entries + image data.
    """
    try:
        with open(ico_path, "rb") as f:
            data = f.read()
        # ICO header: reserved(2) type(2) count(2)
        if len(data) < 6:
            return None
        reserved, ico_type, count = struct.unpack_from("<HHH", data, 0)
        if ico_type != 1:
            return None
        best_size = -1
        best_offset = 0
        best_length = 0
        for i in range(count):
            off = 6 + i * 16
            if off + 16 > len(data):
                break
            width = data[off]      # 0 means 256
            height = data[off + 1]
            w = width if width != 0 else 256
            h = height if height != 0 else 256
            img_size = struct.unpack_from("<I", data, off + 8)[0]
            img_offset = struct.unpack_from("<I", data, off + 12)[0]
            if w * h > best_size:
                best_size = w * h
                best_offset = img_offset
                best_length = img_size
        if best_length == 0 or best_offset + best_length > len(data):
            return None
        img_data = data[best_offset: best_offset + best_length]
        # Check if it's embedded PNG (starts with PNG magic)
        suffix = ".png" if img_data[:4] == b"\x89PNG" else ".bmp"
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        tmp.write(img_data)
        tmp.close()
        return tmp.name
    except Exception:
        return None


def resize_to_128_sips(src_path, dst_path):
    """Use macOS sips to resize image to 128x128 PNG."""
    result = subprocess.run(
        ["sips", "-z", "128", "128", "--setProperty", "format", "png",
         src_path, "--out", dst_path],
        capture_output=True, text=True
    )
    return result.returncode == 0 and os.path.exists(dst_path) and os.path.getsize(dst_path) > 0


def resize_to_128_pil(src_path, dst_path):
    """Use Pillow to resize image to 128x128 PNG."""
    from PIL import Image
    with Image.open(src_path) as img:
        img = img.convert("RGBA")
        img = img.resize((128, 128), Image.LANCZOS)
        img.save(dst_path, "PNG")
    return True


def render_svg_with_qlmanage(svg_path, dst_path):
    """
    Use macOS qlmanage to render SVG to PNG (128x128).
    qlmanage writes to <outdir>/<filename>.png, so we redirect to a temp dir.
    """
    out_dir = tempfile.mkdtemp()
    try:
        result = subprocess.run(
            ["qlmanage", "-t", "-s", "128", "-o", out_dir, svg_path],
            capture_output=True, text=True, timeout=10
        )
        rendered = os.path.join(out_dir, os.path.basename(svg_path) + ".png")
        if os.path.exists(rendered) and os.path.getsize(rendered) > 0:
            import shutil
            shutil.move(rendered, dst_path)
            return True
    except Exception:
        pass
    finally:
        try:
            import shutil
            shutil.rmtree(out_dir, ignore_errors=True)
        except Exception:
            pass
    return False


def try_resize(src_path, dst_path):
    # SVG: use qlmanage
    if src_path.endswith(".svg"):
        return render_svg_with_qlmanage(src_path, dst_path)

    # Try PIL first
    try:
        return resize_to_128_pil(src_path, dst_path)
    except Exception:
        pass

    # Try sips directly
    if resize_to_128_sips(src_path, dst_path):
        return True

    # If ICO, extract largest image first then retry sips
    if src_path.endswith(".ico"):
        extracted = extract_largest_from_ico(src_path)
        if extracted:
            ok = resize_to_128_sips(extracted, dst_path)
            os.unlink(extracted)
            if ok:
                return True

    return False


def download_logo(name, urls):
    """Try each URL; return local temp path on first success, or None."""
    req_headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                      "AppleWebKit/537.36 (KHTML, like Gecko) "
                      "Chrome/120.0.0.0 Safari/537.36"
    }
    # macOS Python may lack system CA bundle; use unverified context for favicon downloads
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    for url in urls:
        try:
            req = urllib.request.Request(url, headers=req_headers)
            with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
                if resp.status != 200:
                    continue
                data = resp.read()
                if len(data) < 100:
                    continue
                ct = resp.headers.get("content-type", "")
                # Determine file type by content-type or magic bytes or URL
                if "svg" in ct or data[:5] in (b"<svg ", b"<?xml") or url.endswith(".svg"):
                    suffix = ".svg"
                elif data[:4] == b"\x89PNG":
                    suffix = ".png"
                elif data[:2] == b"\xff\xd8":
                    suffix = ".jpg"
                elif data[:4] in (b"GIF8", b"GIF9"):
                    suffix = ".gif"
                elif data[:4] == b"\x00\x00\x01\x00":
                    suffix = ".ico"
                elif url.endswith(".ico"):
                    suffix = ".ico"
                else:
                    # Unknown binary format — skip
                    print(f"  [skip] {url}: unknown format ct={ct} magic={data[:4].hex()}", file=sys.stderr)
                    continue
                tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
                tmp.write(data)
                tmp.close()
                return tmp.name
        except Exception as e:
            print(f"  [skip] {url}: {e}", file=sys.stderr)
    return None


def make_icon(name, bg_hex, label, urls):
    out_path = os.path.join(ICONS_DIR, name + ".png")

    tmp_src = download_logo(name, urls)
    if tmp_src:
        ok = try_resize(tmp_src, out_path)
        os.unlink(tmp_src)
        if ok and os.path.exists(out_path) and os.path.getsize(out_path) > 0:
            return out_path, "downloaded"

    # Fallback
    make_fallback_icon(name, bg_hex, label)
    return out_path, "fallback"


# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    total = len(ICONS)
    results = {"downloaded": [], "fallback": []}

    for i, (name, color, label, urls) in enumerate(ICONS):
        path, method = make_icon(name, color, label, urls)
        results[method].append(name)
        status = "OK" if method == "downloaded" else "FALLBACK"
        print(f"[{i+1}/{total}] [{status}] {path}")

    print(f"\nDone. {total} icons in {ICONS_DIR}/")
    print(f"  downloaded: {len(results['downloaded'])} — {', '.join(results['downloaded'])}")
    print(f"  fallback:   {len(results['fallback'])} — {', '.join(results['fallback'])}")
