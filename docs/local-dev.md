# 本地开发环境：后端 + APP 联调

> 目标：本地 `docker-compose` 起 PostgreSQL + 后端，APP 以 AI 托管模式连本地后端，
> 完整跑通「设备注册 → 免费额度 → Agent Chat → 扣费 → 审计」。

## 1. 起后端栈（PostgreSQL + Backend）

```bash
cd /path/to/novel_builder
cp docker-compose.override.yml.example docker-compose.override.yml
# 按需编辑 override：LLM_UPSTREAM_API_KEY 填你的 DeepSeek/其他 OpenAI 兼容 key；
# 本地联调建议 ATTESTATION_REQUIRED=false（无需真机 attestation）。

docker compose up -d postgres backend
docker compose exec backend alembic upgrade head
curl http://localhost:3800/health        # → {"status":"ok"}
```

## 2. 跑 APP（AI 托管模式）

```bash
cd novel_app

# Android 模拟器（10.0.2.2 = 宿主机）
flutter run --dart-define=BACKEND_BASE_URL=http://10.0.2.2:3800

# 真机：改为电脑的局域网 IP
# flutter run --dart-define=BACKEND_BASE_URL=http://192.168.x.x:3800
```

- `BACKEND_BASE_URL` 打包注入后，APP 走 AI 托管模式：
  不再要求配置任何 AI 供应商，首次调用 AI 时自动完成设备注册并领取免费额度。

## 3. 冒烟清单

1. 全新安装 → 打开 Agent Chat 发一句话 → 正常流式回复（消耗免费额度）
2. 额度扣减：`curl -H "X-API-TOKEN: <token>" http://localhost:3800/api/admin/usage/1`
   → `usage` 有 ok 记录、`quota_transactions` 有 free_grant + usage
3. 卸载重装 → 重新注册 → 额度**不**叠加（android_id 去重）
4. 额度清零后再发 → 返回 `insufficient_quota` 错误（UI 可感知）

## 4. Key Attestation 说明

- 生产打包必须设置 `EXPECTED_APK_SIGNATURE_SHA256`（release keystore 的
  SHA-256）并保持 `ATTESTATION_REQUIRED=true`；
- 模拟器/未解锁机型可能只产生 software attestation → 注册会被拒；
- `ATTESTATION_REQUIRED=false` 仅限本地联调（注册跳过证书链验证，
  但额度/审计/扣费逻辑完全一致）。

## 5. 常见问题

- **APP 报 NO_BACKEND**：没传 `--dart-define=BACKEND_BASE_URL`；
- **注册 402/401**：challenge 过期（120 秒）→ 重试；或服务器
  `EXPECTED_APK_SIGNATURE_SHA256` 与调试签名不匹配（debug 包用
  `ATTESTATION_REQUIRED=false` 联调）；
- **alembic 报错**：确认 `DATABASE_URL` 指向正在运行的 postgres
  （compose 内为 `postgresql://novel_user:novel_pass@postgres:5432/novel_db`）。
