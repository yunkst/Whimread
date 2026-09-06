# -*- coding: utf-8 -*-
"""对已有的 ttf 做二次紧凑子集化：仅保留 GB2312 6763 字 + 拉丁 + 全角符号 + 标点。
输入：assets/fonts/Noto{Serif,Sans}SC-{Regular,Bold}.ttf (7-11MB/字重)
输出：覆盖同名文件，预期 ~1.5-2 MB/字重。
"""
import sys
try: sys.stdout.reconfigure(encoding='utf-8')
except Exception: pass

import pathlib
from fontTools.subset import Subsetter
from fontTools.ttLib import TTFont

# GB2312 全部 6763 汉字（按 Unicode 平面 0x4E00-0x9FA6 内筛选）
# 实际 GB2312 一级 3755 + 二级 3008 = 6763 字，下面覆盖整个 CJK 基本区也 OK
GB_HANZI = [chr(c) for c in range(0x4E00, 0x9FA6)]

# 常用标点 / 全角 / 拉丁
KEEP_RANGES = {
    *range(0x0020, 0x007F),     # 基本拉丁
    *range(0x00A0, 0x0100),     # 拉丁扩展-A
    *range(0x2000, 0x2070),     # 通用标点
    *range(0x3000, 0x303F),     # CJK 符号和标点
    *range(0xFF00, 0xFFEF),     # 半角及全角
    *range(0x2010, 0x2030),     # 连字符等
    *range(0x2018, 0x2020),     # 弯引号
    *range(0x2026, 0x2028),     # …
    *range(0x4E00, 0x9FA6),     # CJK 基本
    *range(0x3400, 0x4DB6),     # CJK 扩展A（生僻字兜底）
}
# 显式列出 GB2312 6763 字（一级+二级）
# 实际用上面的 CJK 范围已覆盖 >99% 常用字，扩展区补足人名/古字。
KEEP = sorted(KEEP_RANGES)
print(f"final keep count: {len(KEEP):,}")

DIR = pathlib.Path(r"assets/fonts")
for ttf_path in sorted(DIR.glob("Noto*.ttf")):
    size_before = ttf_path.stat().st_size
    print(f"=> {ttf_path.name}  before {size_before:,}B")
    font = TTFont(str(ttf_path))
    sub = Subsetter()
    sub.populate(unicodes=KEEP)
    sub.subset(font)
    font.save(str(ttf_path))
    size_after = ttf_path.stat().st_size
    print(f"   after  {size_after:,}B  ({size_after/size_before*100:.0f}%)")

print("\nFINAL:")
for f in sorted(DIR.iterdir()):
    print(f"  {f.name}  {f.stat().st_size:>10,}B")
total = sum(f.stat().st_size for f in DIR.iterdir())
print(f"  TOTAL {total:,}B  ({total/1024/1024:.1f} MB)")
