#!/usr/bin/env python3
"""Generate 128x128 PNG icons for AI vendors using pure Python (no deps)."""

import struct
import zlib
import os

ICONS_DIR = "/tmp/mcp-notify/icons"
os.makedirs(ICONS_DIR, exist_ok=True)

# (filename_without_ext, bg_hex, label)
ICONS = [
    # 海外厂商
    ("claude",           "#D97757", "C"),
    ("openai",           "#10A37F", "AI"),
    ("gemini",           "#8AB4F8", "G"),
    ("google-ai-studio", "#4285F4", "GS"),
    ("meta-ai",          "#0082FB", "M"),
    ("copilot",          "#0078D4", "Co"),
    ("azure-openai",     "#0089D6", "Az"),
    ("grok",             "#000000", "X"),
    ("mistral",          "#FF7000", "Mi"),
    ("cohere",           "#39594D", "Co"),
    ("perplexity",       "#20808D", "Px"),
    ("stability-ai",     "#F5A623", "St"),
    ("midjourney",       "#000000", "MJ"),
    ("cursor",           "#000000", "Cu"),
    ("replit",           "#F26207", "Re"),
    ("github-copilot",   "#24292F", "GH"),
    ("amazon-bedrock",   "#FF9900", "AB"),
    ("amazon-q",         "#FF9900", "Q"),
    ("apple-intelligence","#000000","Ap"),
    ("hugging-face",     "#FFD21E", "HF"),
    ("runway",           "#000000", "Rw"),
    ("elevenlabs",       "#000000", "11"),
    ("suno",             "#FFC107", "Su"),
    ("pi-ai",            "#5B5EA6", "Pi"),
    ("character-ai",     "#09B37B", "CA"),
    ("pika",             "#6C63FF", "Pk"),
    ("kling",            "#FF4B4B", "Kl"),
    ("groq",             "#F55036", "Gq"),
    ("together-ai",      "#0A0A0A", "To"),
    ("replicate",        "#000000", "Rp"),
    ("ai21",             "#5C6BC0", "21"),
    ("aleph-alpha",      "#FF5F00", "AA"),
    ("nvidia",           "#76B900", "Nv"),
    ("luma-ai",          "#000000", "La"),
    ("adobe-firefly",    "#FF0000", "Af"),
    ("notion-ai",        "#000000", "No"),
    ("grammarly",        "#15C39A", "Gr"),
    # 国内厂商
    ("ernie-bot",        "#3388FF", "文"),
    ("qwen",             "#6E6EFF", "Q"),
    ("doubao",           "#1D7DFA", "豆"),
    ("coze",             "#1D7DFA", "Cz"),
    ("zhipu",            "#3B82F6", "智"),
    ("kimi",             "#000000", "K"),
    ("deepseek",         "#4D6BFE", "DS"),
    ("yi-ai",            "#FF6B35", "Yi"),
    ("minimax",          "#FF5C5C", "Mx"),
    ("baichuan",         "#0066FF", "百"),
    ("tiangong",         "#00C4CC", "天"),
    ("sensenova",        "#FF4040", "商"),
    ("xunfei-spark",     "#0052D9", "讯"),
    ("hunyuan",          "#07C160", "混"),
    ("step-ai",          "#5B5EA6", "St"),
    ("tencent-yuanbao",  "#07C160", "元"),
    ("youdao-ai",        "#CC0000", "有"),
    ("360-ai",           "#00AA00", "360"),
    ("pangu",            "#CF0A2C", "盘"),
    ("xiaomi-ai",        "#FF6900", "小"),
    ("sogou-ai",         "#FF6600", "搜"),
    ("zidong-taichi",    "#7B2FBE", "紫"),
    ("mobvoi",           "#FF5722", "出"),
    ("characterglm",     "#4A90D9", "角"),
    ("xverse",           "#1A73E8", "元"),
    # AI 开发工具
    ("langchain",        "#1C3C3C", "LC"),
    ("llamaindex",       "#7C3AED", "LI"),
    ("wandb",            "#FFBE00", "W&"),
    ("vercel-ai",        "#000000", "Ve"),
    ("supabase-ai",      "#3ECF8E", "Sb"),
]

SIZE = 128
RADIUS = 24


def hex_to_rgb(h):
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def write_png(path, pixels):
    """Write a SIZE x SIZE RGBA pixel array as PNG."""
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
    """Return SIZE x SIZE boolean mask for rounded rect."""
    mask = [[False] * size for _ in range(size)]
    r = radius
    for y in range(size):
        for x in range(size):
            in_rect = True
            # corners
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


def draw_text_pixels(pixels, text, bg_rgb):
    """Draw centered white text using a simple 5x7 bitmap font."""
    # Minimal ASCII bitmap font (5 wide x 7 tall) for Latin chars
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

    # For CJK / unknown chars, draw a simple filled square
    def get_glyph(ch):
        if ch in FONT:
            return FONT[ch]
        # filled block for CJK
        return [0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F]

    CHAR_W = 5
    CHAR_H = 7
    SCALE = 5  # each pixel = 5x5 block -> chars are 25x35 px
    GAP = SCALE  # gap between chars

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


def make_icon(name, bg_hex, label):
    bg = hex_to_rgb(bg_hex)
    mask = rounded_rect_mask(SIZE, RADIUS)

    pixels = [[(0, 0, 0, 0)] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            if mask[y][x]:
                pixels[y][x] = (bg[0], bg[1], bg[2], 255)

    draw_text_pixels(pixels, label, bg)

    path = os.path.join(ICONS_DIR, name + ".png")
    write_png(path, pixels)
    return path


if __name__ == "__main__":
    total = len(ICONS)
    for i, (name, color, label) in enumerate(ICONS):
        path = make_icon(name, color, label)
        print(f"[{i+1}/{total}] {path}")
    print(f"\nDone. Generated {total} icons in {ICONS_DIR}/")
