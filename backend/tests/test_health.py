#!/usr/bin/env python3
"""
健康检查与服务信息端点契约测试.

- GET /health - 服务自身健康 (公开)
- GET / - 服务信息 + 端点清单 (公开)
- GET /text2img/health - ComfyUI 健康检查 (需 token, 外部 ComfyUI 必须被 mock)
- GET /security-check - 仅 DEBUG 可用

注: main.py 的 /text2img/health 内部调 create_comfyui_client() 得到 ComfyUIClient,
再 await client.health_check()。ComfyUIClient 用 httpx 异步访问 ComfyUI /system_stats。
测试通过 monkeypatch app.main.create_comfyui_client 返回 FakeComfyUIClient,
不真连 ComfyUI。
"""

from __future__ import annotations

import pytest


def test_health_returns_ok(client):
    """GET /health 公开端点, 返回 {"status": "ok"}."""
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_root_returns_service_info(client):
    """GET / 公开端点, 返回服务信息 + 端点清单."""
    r = client.get("/")
    assert r.status_code == 200
    body = r.json()
    assert body["message"] == "Whimread Backend"
    # 端点清单非空
    assert isinstance(body["endpoints"], list)
    assert len(body["endpoints"]) > 0
    # token_required 字段存在
    assert "token_required" in body
    # features 列表存在
    assert isinstance(body.get("features"), list)


def test_security_check_disabled_in_non_debug(client):
    """DEBUG=false 时 /security-check 应 404 (端点关闭)."""
    r = client.get("/security-check")
    assert r.status_code == 404


@pytest.mark.auth
def test_text2img_health_with_mocked_comfyui_healthy(
    client, auth_headers, monkeypatch
):
    """ComfyUI 返回 True → 健康检查 healthy.

    main.py /text2img/health 内部:
        client = create_comfyui_client()
        healthy = await client.health_check()
    所以 patch app.main.create_comfyui_client 返回一个 health_check 返回 True 的 fake。
    """
    import app.main as main_module

    class FakeComfyUIClient:
        async def health_check(self) -> bool:
            return True

    monkeypatch.setattr(
        main_module, "create_comfyui_client", lambda *a, **kw: FakeComfyUIClient()
    )

    r = client.get("/text2img/health", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "healthy"
    assert body["services"]["comfyui"] is True
    assert body["services"]["api_accessible"] is True


@pytest.mark.auth
def test_text2img_health_with_comfyui_unreachable(
    client, auth_headers, monkeypatch
):
    """ComfyUI 返回 False (不可达) → unhealthy, 但端点本身仍 200."""
    import app.main as main_module

    class FakeComfyUIClient:
        async def health_check(self) -> bool:
            return False

    monkeypatch.setattr(
        main_module, "create_comfyui_client", lambda *a, **kw: FakeComfyUIClient()
    )

    r = client.get("/text2img/health", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "unhealthy"
    assert body["services"]["comfyui"] is False


@pytest.mark.auth
def test_text2img_health_with_comfyui_exception(
    client, auth_headers, monkeypatch
):
    """ComfyUI client 抛异常 → unhealthy, 端点仍 200 (main.py 内 catch)."""
    import app.main as main_module

    class FakeComfyUIClient:
        async def health_check(self) -> bool:
            raise OSError("connection refused")

    monkeypatch.setattr(
        main_module, "create_comfyui_client", lambda *a, **kw: FakeComfyUIClient()
    )

    r = client.get("/text2img/health", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "unhealthy"
    assert body["services"]["comfyui"] is False
