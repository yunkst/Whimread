# feedback 云函数

用户问题反馈 + 客户端日志批量上报的接收端,匹配 `cloudbase/migrations/20260909100000_feedback_reports.sql` 表结构。

## 路由

| Method | Path | 鉴权 | 用途 |
|---|---|---|---|
| POST | `/api/v1/feedback/submit` | Device JWT | 用户报告(可选附日志) |
| POST | `/api/logs/upload` | Device JWT | `LogReporterService` 自动批量上报 |
| GET  | `/api/v1/feedback/list` | `X-API-TOKEN` | 管理端列出报告 |
| GET  | `/api/v1/feedback/detail?id=N` | `X-API-TOKEN` | 管理端单条 + 附带日志 |
| GET  | `/api/v1/feedback/logs?device_id=X&since=&until=&level=` | `X-API-TOKEN` | 管理端按设备拉流式日志 |

## 环境变量

| 变量 | 用途 |
|---|---|
| `DEVICE_JWT_PUBLIC_KEY` | JWT 验签公钥(与 device-auth 共用) |
| `TCB_ENV_ID` | PG 控制面调用所需 |
| `PUBLISH_API_TOKEN` | 管理端 `X-API-TOKEN` 校验值(与 app-release 共用) |

## 部署

```bash
node scripts/cloudbase/sync-common.mjs          # 同步 common/ 到函数目录
tcb fn deploy feedback -e $ENV_ID
tcb fn config update feedback -e $ENV_ID --env '{
  "DEVICE_JWT_PUBLIC_KEY": "...",
  "TCB_ENV_ID": "...",
  "PUBLISH_API_TOKEN": "..."
}'
```

数据库迁移:`cloudbase/migrations/20260909100000_feedback_reports.sql`,随 `migrate.sh` 自动应用。

## 本地拉取

```bash
FEEDBACK_API_BASE=https://whimread.dazhi.site \
PUBLISH_API_TOKEN=$WHIMREAD_BACKEND_TOKEN \
node scripts/cloudbase/feedback-fetch.mjs --limit 20

node scripts/cloudbase/feedback-fetch.mjs --id 123
node scripts/cloudbase/feedback-fetch.mjs --kind native_crash --status open --since 2026-09-01
```

## 入参 / 出参限制

- body ≤ 512 KB
- 报告标题 ≤ 200 字符,描述 / 复现 ≤ 5000,联系方式 ≤ 200
- 单报告附日志 ≤ 300 条,`/upload` 单批 ≤ 50 条
- 单条日志 `message ≤ 500`,`stack_trace ≤ 4000`,`tags ≤ 10 × 100`
- 60 s / device 最多 5 次 submit(进程内 LRU)

错误码沿用 `common/errors.js`:`BAD_REQUEST / NOT_FOUND / INTERNAL / JWT_INVALID`,新增 `PAYLOAD_TOO_LARGE / RATE_LIMITED / UNAUTHORIZED`。