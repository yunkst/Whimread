#!/usr/bin/env python3
"""
注册 challenge 的一次性存储 + 注册接口的 IP 限速。

内存实现（进程内有效），重启即失效——challenge 本就是 60 秒级一次性凭证，
不需要持久化；多副本部署时需替换为 Redis（本期单实例部署，明确接受）。
"""

import secrets
import threading
import time
from dataclasses import dataclass, field


@dataclass
class _Challenge:
    nonce: str
    created_at: float
    used: bool = False


@dataclass
class _IpWindow:
    timestamps: list[float] = field(default_factory=list)


class ChallengeStore:
    """一次性 challenge + 每 IP 注册速率限制（线程安全）。"""

    def __init__(self, ttl_seconds: int = 120, max_per_hour: int = 5):
        self._ttl = ttl_seconds
        self._max_per_hour = max_per_hour
        self._lock = threading.Lock()
        self._challenges: dict[str, _Challenge] = {}
        self._ip_windows: dict[str, _IpWindow] = {}

    def issue(self, ip: str) -> str:
        """签发 challenge；同 IP 超过每小时配额时抛 RateLimitError。

        签发同时做惰性清理（过期 challenge / 窗口外时间戳）。
        """
        now = time.monotonic()
        with self._lock:
            self._cleanup_locked(now)

            window = self._ip_windows.setdefault(ip, _IpWindow())
            window.timestamps = [t for t in window.timestamps if now - t < 3600]
            if len(window.timestamps) >= self._max_per_hour:
                from ..exceptions import RateLimitError

                raise RateLimitError(
                    "该网络注册请求过于频繁，请稍后再试",
                    error_code="REGISTER_RATE_LIMITED",
                )
            window.timestamps.append(now)

            nonce = secrets.token_urlsafe(32)
            self._challenges[nonce] = _Challenge(nonce=nonce, created_at=now)
            return nonce

    def consume(self, nonce: str) -> bool:
        """一次性消费 challenge：存在、未用、未过期才成功。"""
        now = time.monotonic()
        with self._lock:
            ch = self._challenges.get(nonce)
            if ch is None or ch.used or now - ch.created_at > self._ttl:
                return False
            ch.used = True
            return True

    def _cleanup_locked(self, now: float) -> None:
        expired = [
            n for n, c in self._challenges.items() if now - c.created_at > self._ttl
        ]
        for n in expired:
            del self._challenges[n]
        dead_ips = [
            ip
            for ip, w in self._ip_windows.items()
            if not w.timestamps or now - w.timestamps[-1] > 3600
        ]
        for ip in dead_ips:
            del self._ip_windows[ip]


# 进程级单例（由 devices 路由使用；测试可自行构造实例注入）
challenge_store = ChallengeStore()
