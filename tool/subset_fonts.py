# -*- coding: utf-8 -*-
"""Noto CJK 字体子集化：下载 SubsetOTF → pyftsubset 子集化 → 转 ttf。"""
import sys
try:
    sys.stdout.reconfigure(encoding='utf-8')   # 避免 Windows GBK 崩溃
except Exception:
    pass
import io, time, urllib.request, pathlib
from fontTools.subset import Subsetter
from fontTools.ttLib import TTFont

# 保留字符集合：基本拉丁 + 拉丁扩展 + 通用/CJK 标点 + 全角 + CJK 基本 + 扩展A
RANGES = [
    (0x0020, 0x007F), (0x00A0, 0x0100), (0x2010, 0x2030),
    (0x2018, 0x201F), (0x2026, 0x2027), (0x3000, 0x303F),
    (0x3400, 0x4DB6), (0x4E00, 0x9FA6), (0xFF00, 0xFFEF),
]
KEEP = sorted({c for s, e in RANGES for c in range(s, e)})
print(f"subset unicode count: {len(KEEP):,}")

OUT = pathlib.Path(r"assets/fonts")
OUT.mkdir(parents=True, exist_ok=True)

BASE_SANS = "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Sans/SubsetOTF/SC/{f}"
BASE_SERIF = "https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@main/Serif/SubsetOTF/SC/{f}"
TARGETS = [
    ("NotoSansSC-Regular",  BASE_SANS.format(f="NotoSansSC-Regular.otf")),
    ("NotoSansSC-Bold",     BASE_SANS.format(f="NotoSansSC-Bold.otf")),
    ("NotoSerifSC-Regular", BASE_SERIF.format(f="NotoSerifSC-Regular.otf")),
    ("NotoSerifSC-Bold",    BASE_SERIF.format(f="NotoSerifSC-Bold.otf")),
]

def fetch(url):
    print(f"  GET {url[:88]}")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return io.BytesIO(r.read())

def subset(in_bytes, out_path):
    ttf = TTFont(in_bytes)
    sub = Subsetter()
    sub.populate(unicodes=KEEP)
    sub.subset(ttf)
    ttf.save(str(out_path))   # fontTools 按扩展名存 ttf

for name, url in TARGETS:
    out = OUT / f"{name}.ttf"
    if out.exists() and out.stat().st_size > 1_000_000:
        print(f"SKIP {name} (exists {out.stat().st_size:,}B)"); continue
    print(f"=> {name}")
    t0 = time.time()
    data = fetch(url)
    print(f"   raw {len(data.getvalue()):,}B, subsetting...")
    subset(data, out)
    print(f"   OK {name}.ttf -> {out.stat().st_size:,}B  ({time.time()-t0:.1f}s)")

print("\nDONE. dir:")
for f in sorted(OUT.iterdir()):
    print(f"  {f.name}  {f.stat().st_size:,}B")
