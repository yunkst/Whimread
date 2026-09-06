#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
交互式使用后台 API 服务的脚本
功能：
- 自动探测后台地址首页信息，识别令牌头名称与是否需要令牌
- 支持搜索小说、查看章节列表、读取章节内容
- 可选保存章节内容为 UTF-8 文本文件，减少中文乱码问题

运行：
    python novel_api_cli.py

可选环境变量：
    NOVEL_API_BASE_URL  后台服务地址，默认 http://localhost:3800
"""

import os
import re
import sys
import json
from typing import Any, Dict, List, Optional, Tuple

import requests


# 尝试将标准输出改为 UTF-8，以减少 PowerShell 下中文乱码
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


DEFAULT_BASE_URL = os.environ.get("NOVEL_API_BASE_URL", "http://localhost:3800")


def fetch_index(base_url: str) -> Tuple[str, bool, Optional[Dict[str, Any]]]:
    """获取后端首页信息，返回 (token_header, token_required, index_json)。"""
    try:
        url = base_url.rstrip("/") + "/"
        r = requests.get(url, timeout=5)
        r.raise_for_status()
        data = r.json()
        token_header = data.get("token_header", "X-API-TOKEN")
        token_required = bool(data.get("token_required", True))
        return token_header, token_required, data
    except Exception:
        # 无法获取首页信息时，使用默认值
        return "X-API-TOKEN", True, None


def build_headers(token_header: str, token_value: Optional[str]) -> Dict[str, str]:
    headers: Dict[str, str] = {}
    if token_value:
        headers[token_header] = token_value
    return headers


def api_get(base_url: str, path: str, params: Optional[Dict[str, Any]] = None,
            headers: Optional[Dict[str, str]] = None, timeout: int = 15) -> Any:
    """封装 GET 请求，自动拼接 base_url 与 path。"""
    url = base_url.rstrip("/") + path
    r = requests.get(url, params=params or {}, headers=headers or {}, timeout=timeout)
    r.raise_for_status()
    # 尝试解析 JSON
    try:
        return r.json()
    except Exception:
        return r.text


def safe_filename(name: str) -> str:
    name = re.sub(r"[\\/:*?\"<>|]+", "_", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name or "chapter"


def print_novel_list(novels: List[Dict[str, Any]]) -> None:
    if not novels:
        print("\n未找到任何小说结果。")
        return
    print(f"\n共找到 {len(novels)} 条结果：")
    for idx, n in enumerate(novels):
        title = n.get("title") or "(无标题)"
        author = n.get("author") or "未知"
        url = n.get("url") or ""
        print(f"[{idx}] {title} / {author}\n    {url}")


def print_chapter_list(chapters: List[Dict[str, Any]]) -> None:
    if not chapters:
        print("\n未找到章节列表。")
        return
    print(f"\n共找到 {len(chapters)} 个章节：")
    for idx, ch in enumerate(chapters):
        title = ch.get("title") or "(无标题)"
        print(f"[{idx}] {title}")


def do_search_flow(base_url: str, token_header: str, token_value: Optional[str]) -> None:
    kw = input("\n请输入搜索关键词：").strip()
    if not kw:
        print("关键词不能为空。")
        return
    headers = build_headers(token_header, token_value)
    try:
        novels = api_get(base_url, "/search", params={"keyword": kw}, headers=headers)
        if not isinstance(novels, list):
            print("搜索结果格式异常：", novels)
            return
        print_novel_list(novels)
        if not novels:
            return
        # 选择小说
        while True:
            choice = input("\n选择小说序号，或输入 b 返回：").strip().lower()
            if choice == "b":
                return
            try:
                idx = int(choice)
                if idx < 0 or idx >= len(novels):
                    print("序号越界，请重新输入。")
                    continue
                selected = novels[idx]
                novel_url = selected.get("url") or ""
                if not novel_url:
                    print("该条目缺少 URL。")
                    return
                # 拉取章节列表
                chapters = api_get(base_url, "/chapters", params={"url": novel_url}, headers=headers)
                if not isinstance(chapters, list):
                    print("章节列表格式异常：", chapters)
                    return
                print_chapter_list(chapters)
                if not chapters:
                    return
                # 选择章节
                while True:
                    csel = input("\n选择章节序号，或输入 b 返回：").strip().lower()
                    if csel == "b":
                        return
                    try:
                        cidx = int(csel)
                        if cidx < 0 or cidx >= len(chapters):
                            print("序号越界，请重新输入。")
                            continue
                        ch = chapters[cidx]
                        ch_url = ch.get("url") or ""
                        if not ch_url:
                            print("该章节缺少 URL。")
                            return
                        # 获取章节内容
                        content_obj = api_get(base_url, "/chapter-content", params={"url": ch_url}, headers=headers)
                        if not isinstance(content_obj, dict):
                            print("章节内容格式异常：", content_obj)
                            return
                        title = content_obj.get("title") or "章节内容"
                        content = content_obj.get("content") or "(无内容)"
                        print("\n" + "=" * 60)
                        print(f"标题：{title}\n")
                        print(content)
                        print("=" * 60)
                        # 是否保存到文件
                        save = input("\n是否保存为 UTF-8 文本文件？(y/n)：").strip().lower()
                        if save == "y":
                            folder = os.path.join(os.getcwd(), "output")
                            os.makedirs(folder, exist_ok=True)
                            fname = safe_filename(title) + ".txt"
                            fpath = os.path.join(folder, fname)
                            try:
                                with open(fpath, "w", encoding="utf-8") as f:
                                    f.write(title + "\n\n" + content)
                                print(f"已保存：{fpath}")
                            except Exception as e:
                                print(f"保存失败：{e}")
                        # 是否继续同一本书的其他章节
                        again = input("\n是否继续选择其他章节？(y/n)：").strip().lower()
                        if again != "y":
                            return
                    except ValueError:
                        print("请输入有效数字或 b。")
            except ValueError:
                print("请输入有效数字或 b。")
    except requests.exceptions.HTTPError as e:
        print(f"HTTP 错误：{e}")
    except requests.exceptions.RequestException as e:
        print(f"网络错误：{e}")
    except Exception as e:
        print(f"发生异常：{e}")


def main() -> None:
    print("欢迎使用 Whimread 后台 API 交互脚本")
    base_url = DEFAULT_BASE_URL
    print(f"默认后台地址：{base_url}")
    # 允许用户修改后台地址
    edit = input("是否修改后台地址？(y/n)：").strip().lower()
    if edit == "y":
        new_url = input("请输入后台地址 (例如 http://localhost:3800)：").strip()
        if new_url:
            base_url = new_url

    token_header, token_required, index_info = fetch_index(base_url)
    if index_info:
        print("后端首页信息：", json.dumps(index_info, ensure_ascii=False))
    print(f"令牌头名称：{token_header}")
    print(f"是否需要令牌：{'是' if token_required else '否'}")

    token_value: Optional[str] = None
    if token_required:
        token_value = input(f"请输入令牌 ({token_header})：").strip()
    else:
        use_token = input("后端未要求令牌，是否仍提供令牌？(y/n)：").strip().lower()
        if use_token == "y":
            token_value = input(f"请输入令牌 ({token_header})：").strip()

    # 主菜单循环
    while True:
        print("\n=== 主菜单 ===")
        print("1) 搜索小说")
        print("2) 修改后台地址")
        print("3) 修改令牌")
        print("q) 退出")
        cmd = input("请输入选项：").strip().lower()
        if cmd == "1":
            do_search_flow(base_url, token_header, token_value)
        elif cmd == "2":
            new_url = input("请输入新的后台地址：").strip()
            if new_url:
                base_url = new_url
                token_header, token_required, index_info = fetch_index(base_url)
                print(f"令牌头名称更新为：{token_header}，是否需要令牌：{'是' if token_required else '否'}")
        elif cmd == "3":
            token_value = input(f"请输入新的令牌 ({token_header})：").strip()
        elif cmd == "q":
            print("已退出。")
            break
        else:
            print("无效选项，请重新输入。")


if __name__ == "__main__":
    main()