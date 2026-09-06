#!/usr/bin/env python3
"""
LLM 代理：/v1/chat/completions（OpenAI 兼容，流式 + 非流式）。

职责链：设备 JWT 鉴权 → 余额检查 → 覆写 model → httpx 流式转发上游 →
按 usage 扣额度 → 写 usage_logs / quota_transactions 审计。

SSE 契约（APP 侧 llm_provider_sse.dart 依赖）：
- data: {JSON}\n 帧 + data: [DONE] 哨兵，chunked 透传不整体缓冲
- delta.content / delta.reasoning_content / delta.tool_calls[index] /
  finish_reason / 末帧 usage 全部原样保留
- usage-only 帧（choices 为空数组）不得丢弃

错误语义：握手阶段（建连/上游响应前）失败 → 返回真实 HTTP >=400 状态码，
APP 走既有传输层重试；流建立后中断 → 只能记审计（interrupted），APP 走
回合层重试（RetryEvent 尾部截断机制）。
"""

import asyncio
import json
import logging
import time
from collections.abc import AsyncIterator

import httpx
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, StreamingResponse
from sqlalchemy.orm import Session

from ...config import settings
from ...database import get_db
from ...deps.device_auth import verify_device
from ...exceptions import ExternalServiceError, RateLimitError, ValidationError
from ...models import Device
from ...services.quota import deduct_quota, record_usage, touch_device

logger = logging.getLogger(__name__)

router = APIRouter(tags=["llm-proxy"])

# 每设备并发 1：同一设备同时只能有一个在途 LLM 调用（进程内，重启即清）
_device_locks: dict[int, asyncio.Lock] = {}

# 计费：每 1000 token 记 1 点，单次成功调用最少 1 点
_TOKENS_PER_POINT = 1000


def _lock_for(device_id: int) -> asyncio.Lock:
    lock = _device_locks.get(device_id)
    if lock is None:
        lock = asyncio.Lock()
        _device_locks[device_id] = lock
    return lock


def _require_upstream() -> tuple[str, str, str]:
    base = settings.llm_upstream_base_url.strip().rstrip("/")
    key = settings.llm_upstream_api_key
    model = settings.llm_upstream_model
    if not (base and key and model):
        raise ExternalServiceError(
            "LLM 上游未配置", error_code="LLM_UPSTREAM_NOT_CONFIGURED"
        )
    return base, key, model


def _cost_from_tokens(prompt_tokens: int, completion_tokens: int) -> int:
    total = prompt_tokens + completion_tokens
    return max(1, (total + _TOKENS_PER_POINT - 1) // _TOKENS_PER_POINT)


def _estimate_cost_from_chars(text_chars: int) -> int:
    """无 usage 帧时的兜底估算：~4 字符 ≈ 1 token。"""
    return max(1, (text_chars // 4 + _TOKENS_PER_POINT - 1) // _TOKENS_PER_POINT)


def _public_error(error_code: str, message: str) -> dict:
    """OpenAI 风格错误响应体。"""
    return {"error": {"code": error_code, "message": message}}


class _SseUsageProbe:
    """透传 SSE 流时旁路解析：累计 delta 文本长度 + 捕获末帧 usage。"""

    def __init__(self) -> None:
        self.prompt_tokens: int | None = None
        self.completion_tokens: int | None = None
        self.text_chars = 0
        self._line_buf = b""

    def feed(self, chunk: bytes) -> None:
        self._line_buf += chunk
        while b"\n" in self._line_buf:
            line, self._line_buf = self._line_buf.split(b"\n", 1)
            self._feed_line(line.decode("utf-8", errors="replace").strip())

    def _feed_line(self, line: str) -> None:
        if not line.startswith("data:"):
            return
        payload = line[5:].strip()
        if not payload or payload == "[DONE]":
            return
        try:
            frame = json.loads(payload)
        except json.JSONDecodeError:
            return
        for choice in frame.get("choices") or []:
            content = (choice.get("delta") or {}).get("content")
            if isinstance(content, str):
                self.text_chars += len(content)
        usage = frame.get("usage")
        if isinstance(usage, dict):
            if isinstance(usage.get("prompt_tokens"), int):
                self.prompt_tokens = usage["prompt_tokens"]
            if isinstance(usage.get("completion_tokens"), int):
                self.completion_tokens = usage["completion_tokens"]

    def final_cost(self) -> int:
        if self.prompt_tokens is not None and self.completion_tokens is not None:
            return _cost_from_tokens(self.prompt_tokens, self.completion_tokens)
        return _estimate_cost_from_chars(self.text_chars)


@router.post("/v1/chat/completions")
async def chat_completions(
    request: Request,
    device: Device = Depends(verify_device),
    db: Session = Depends(get_db),
):
    """OpenAI 兼容代理（模型由服务端强制指定，客户端无选择权）。"""
    base, upstream_key, model = _require_upstream()

    lock = _lock_for(device.id)
    if lock.locked():
        raise RateLimitError("该设备已有请求在处理中", error_code="DEVICE_BUSY")

    try:
        body = await request.json()
    except Exception as e:
        raise ValidationError("请求体不是合法 JSON", error_code="INVALID_JSON") from e
    if not isinstance(body, dict):
        raise ValidationError("请求体必须是 JSON 对象", error_code="INVALID_JSON")

    stream = bool(body.get("stream"))
    body["model"] = model  # 模型选择权在服务端
    body.setdefault("stream", False)

    # 余额门槛：≤0 直接拒绝（本轮 0 消耗）
    if device.quota_balance <= 0:
        record_usage(
            db, device.id, model=model, status="insufficient_quota", error="balance<=0"
        )
        db.commit()
        return JSONResponse(
            status_code=402,
            content=_public_error("insufficient_quota", "免费额度已用完"),
        )

    started = time.monotonic()
    headers = {
        "Authorization": f"Bearer {upstream_key}",
        "Content-Type": "application/json",
    }

    # 握手（含上游可达性检查）在返回响应前完成——保证 >=400 时 APP 能感知状态码
    client = httpx.AsyncClient(timeout=httpx.Timeout(300, connect=15))
    try:
        req = client.build_request(
            "POST", f"{base}/chat/completions", json=body, headers=headers
        )
        resp = await client.send(req, stream=stream)
    except httpx.HTTPError as e:
        await client.aclose()
        latency = int((time.monotonic() - started) * 1000)
        record_usage(
            db,
            device.id,
            model=model,
            status="upstream_error",
            error=str(e)[:500],
            latency_ms=latency,
        )
        db.commit()
        return JSONResponse(
            status_code=502,
            content=_public_error("upstream_error", "上游服务暂时不可用"),
        )

    if resp.status_code != 200:
        await resp.aclose()
        await client.aclose()
        latency = int((time.monotonic() - started) * 1000)
        record_usage(
            db,
            device.id,
            model=model,
            status="upstream_error",
            error=f"upstream {resp.status_code}",
            latency_ms=latency,
        )
        db.commit()
        return JSONResponse(
            status_code=502,
            content=_public_error("upstream_error", "上游服务返回错误"),
        )

    if stream:
        await lock.acquire()
        probe = _SseUsageProbe()
        return StreamingResponse(
            _stream_passthrough(client, resp, device, db, model, started, probe, lock),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    return await _forward_blocking(resp, client, device, db, model, started)


async def _forward_blocking(
    resp: httpx.Response,
    client: httpx.AsyncClient,
    device: Device,
    db: Session,
    model: str,
    started: float,
):
    try:
        latency = int((time.monotonic() - started) * 1000)
        data = resp.json()
    finally:
        await resp.aclose()
        await client.aclose()

    usage = data.get("usage") or {}
    pt = int(usage.get("prompt_tokens") or 0)
    ct = int(usage.get("completion_tokens") or 0)
    if pt or ct:
        cost = _cost_from_tokens(pt, ct)
    else:
        text = "".join(
            str((c.get("message") or {}).get("content") or "")
            for c in data.get("choices") or []
        )
        cost = _estimate_cost_from_chars(len(text))

    if not deduct_quota(db, device.id, cost, ref=None):
        record_usage(
            db, device.id, model=model, status="insufficient_quota", latency_ms=latency
        )
        db.commit()
        return JSONResponse(
            status_code=402,
            content=_public_error("insufficient_quota", "免费额度已用完"),
        )
    record_usage(
        db,
        device.id,
        model=model,
        status="ok",
        quota_cost=cost,
        prompt_tokens=pt or None,
        completion_tokens=ct or None,
        latency_ms=latency,
    )
    touch_device(db, device.id)
    db.commit()
    return JSONResponse(status_code=200, content=data)


async def _stream_passthrough(
    client: httpx.AsyncClient,
    resp: httpx.Response,
    device: Device,
    db: Session,
    model: str,
    started: float,
    probe: _SseUsageProbe,
    lock: asyncio.Lock,
) -> AsyncIterator[bytes]:
    """流式透传：chunk 原样转发，旁路解析 usage，结束后扣费落审计。"""
    try:
        completed = False
        try:
            async for chunk in resp.aiter_bytes():
                probe.feed(chunk)
                yield chunk
            completed = True
        except httpx.HTTPError as e:
            logger.warning("Stream interrupted for device %s: %s", device.id, e)
            record_usage(
                db, device.id, model=model, status="interrupted", error=str(e)[:500]
            )
            db.commit()
            return

        if completed:
            cost = probe.final_cost()
            if not deduct_quota(db, device.id, cost):
                record_usage(
                    db,
                    device.id,
                    model=model,
                    status="insufficient_quota",
                    prompt_tokens=probe.prompt_tokens,
                    completion_tokens=probe.completion_tokens,
                )
            else:
                record_usage(
                    db,
                    device.id,
                    model=model,
                    status="ok",
                    quota_cost=cost,
                    prompt_tokens=probe.prompt_tokens,
                    completion_tokens=probe.completion_tokens,
                    latency_ms=int((time.monotonic() - started) * 1000),
                )
            touch_device(db, device.id)
            db.commit()
    finally:
        await resp.aclose()
        await client.aclose()
        lock.release()
