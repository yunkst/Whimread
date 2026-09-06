#!/usr/bin/env python3
"""
设备注册（challenge / register / me）测试。

attestation 验证通过 monkeypatch 替换为受控假实现——真实验证器需要 TEE
硬件证书链，无法离线构造；verifier 本身的解析逻辑由专门的单元测试覆盖
（test_device_attestation.py，用自签链验证结构解析与拒绝路径）。
"""

from datetime import UTC, datetime, timedelta

import pytest

from app.api.routes import devices as devices_route
from app.config import settings
from app.services import device_token

# fresh_challenge_store / attestation_off / attestation_ok 由 conftest 提供


def _register(client, android_id="abc123def456", challenge_override=None, **overrides):
    body = {"android_id": android_id, "platform": "android", "app_version": "2.1.0"}
    body.update(overrides)
    body["challenge"] = (
        challenge_override or (client.post("/api/v1/devices/challenge").json()["nonce"])
    )
    return client.post("/api/v1/devices/register", json=body)


class TestChallenge:
    def test_challenge_签发并声明attestation要求(self, client):
        resp = client.post("/api/v1/devices/challenge")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["nonce"]) >= 32
        assert data["attestation_required"] is True  # settings 默认

    def test_challenge_一次性_重复消费失效(self, client, attestation_off):
        first = client.post("/api/v1/devices/challenge").json()["nonce"]
        # 用第一个 nonce 注册成功后，再用它注册第二次必须 401
        assert _register(client, challenge_override=first).status_code == 200
        body = {"android_id": "other-device-01", "challenge": first}
        resp = client.post("/api/v1/devices/register", json=body)
        assert resp.status_code == 401
        assert resp.json()["error"] == "CHALLENGE_INVALID"

    def test_challenge_同IP超速被限(self, client):
        for _ in range(5):
            assert client.post("/api/v1/devices/challenge").status_code == 200
        resp = client.post("/api/v1/devices/challenge")
        assert resp.status_code == 429
        assert resp.json()["error"] == "REGISTER_RATE_LIMITED"


class TestRegister:
    def test_注册成功_发放免费额度并返回JWT(self, client, attestation_ok, monkeypatch):
        monkeypatch.setattr(settings, "device_free_quota", 500)
        resp = _register(client)
        assert resp.status_code == 200
        data = resp.json()
        assert data["quota_balance"] == 500
        assert data["attestation_verified"] is True
        assert data["device_id"] > 0
        # JWT 可被 /me 识别
        me = client.get(
            "/api/v1/devices/me",
            headers={"Authorization": f"Bearer {data['token']}"},
        )
        assert me.status_code == 200
        assert me.json()["quota_balance"] == 500
        assert me.json()["attestation_verified"] is True

    def test_卸载重装_同android_id不重复发额度(self, client, attestation_ok):
        first = _register(client, android_id="same-device-1234").json()
        assert first["quota_balance"] == 500
        second = _register(client, android_id="same-device-1234").json()
        assert second["quota_balance"] == 500, "同设备重注册不得叠加额度"
        assert second["device_id"] == first["device_id"]

    def test_attestation失败_注册被拒(self, client, monkeypatch):
        monkeypatch.setattr(settings, "attestation_required", True)

        def _fail(**kwargs):
            from app.exceptions import AuthenticationError

            raise AuthenticationError(
                "APK 签名与官方发行版不符",
                error_code="ATTESTATION_SIGNATURE_MISMATCH",
            )

        monkeypatch.setattr(devices_route, "verify_key_attestation", _fail)
        resp = _register(client)
        assert resp.status_code == 401
        assert resp.json()["error"] == "ATTESTATION_SIGNATURE_MISMATCH"

    def test_无效challenge_拒绝(self, client, attestation_off):
        body = {"android_id": "abc123def456", "challenge": "bogus-nonce"}
        resp = client.post("/api/v1/devices/register", json=body)
        assert resp.status_code == 401


class TestDeviceToken:
    def test_jwt往返(self):
        token = device_token.issue_device_token(42)
        assert device_token.verify_device_token(token) == 42

    def test_过期token被拒(self):
        from app.exceptions import AuthenticationError

        # 手工造一个已过期的 payload
        expired = device_token.jwt.encode(
            {
                "sub": "1",
                "typ": "device",
                "iat": datetime.now(UTC) - timedelta(days=2),
                "exp": datetime.now(UTC) - timedelta(days=1),
            },
            settings.secret_key,
            algorithm=settings.jwt_algorithm,
        )
        with pytest.raises(AuthenticationError) as exc:
            device_token.verify_device_token(expired)
        assert exc.value.error_code == "DEVICE_TOKEN_EXPIRED"

    def test_篡改token被拒(self):
        from app.exceptions import AuthenticationError

        token = device_token.issue_device_token(1) + "x"
        with pytest.raises(AuthenticationError) as exc:
            device_token.verify_device_token(token)
        assert exc.value.error_code == "DEVICE_TOKEN_INVALID"

    def test_非device类型token被拒(self):
        from app.exceptions import AuthenticationError

        other = device_token.jwt.encode(
            {"sub": "1", "typ": "admin"}, settings.secret_key, algorithm="HS256"
        )
        with pytest.raises(AuthenticationError):
            device_token.verify_device_token(other)
